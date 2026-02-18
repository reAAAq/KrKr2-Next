#include "engine_api.h"

#if defined(ENGINE_API_USE_KRKR2_RUNTIME)

#include <new>
#include <string>
#include <unordered_set>
#include <mutex>
#include <thread>
#include <memory>

#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>

#include "environ/Application.h"
#include "environ/cocos2d/AppDelegate.h"
#include "base/SysInitIntf.h"
#include "base/impl/SysInitImpl.h"

struct engine_handle_s {
  std::mutex mutex;
  std::string last_error;
  int state = 0;
  std::thread::id owner_thread;
  bool runtime_owner = false;
};

namespace {

enum class EngineState {
  kCreated = 0,
  kOpened,
  kPaused,
  kDestroyed,
};

inline int ToStateValue(EngineState state) {
  return static_cast<int>(state);
}

std::mutex g_registry_mutex;
std::unordered_set<engine_handle_t> g_live_handles;
thread_local std::string g_thread_error;
engine_handle_t g_runtime_owner = nullptr;
bool g_runtime_active = false;
bool g_runtime_started_once = false;
std::unique_ptr<TVPAppDelegate> g_host_app_delegate;
bool g_cocos_bootstrapped = false;
std::once_flag g_loggers_init_once;

std::shared_ptr<spdlog::logger> EnsureNamedLogger(const char* name) {
  if (auto logger = spdlog::get(name); logger != nullptr) {
    return logger;
  }
  return spdlog::stdout_color_mt(name);
}

void EnsureRuntimeLoggersInitialized() {
  std::call_once(g_loggers_init_once, []() {
    spdlog::set_level(spdlog::level::debug);
    auto core_logger = EnsureNamedLogger("core");
    EnsureNamedLogger("tjs2");
    EnsureNamedLogger("plugin");
    if (core_logger != nullptr) {
      spdlog::set_default_logger(core_logger);
    }
  });
}

void SetThreadError(const char* message) {
  g_thread_error = (message != nullptr) ? message : "";
}

engine_result_t SetThreadErrorAndReturn(engine_result_t result,
                                        const char* message) {
  SetThreadError(message);
  return result;
}

bool IsHandleLiveLocked(engine_handle_t handle) {
  return g_live_handles.find(handle) != g_live_handles.end();
}

engine_result_t ValidateHandleLocked(engine_handle_t handle,
                                     engine_handle_s** out_impl) {
  if (handle == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine handle is null");
  }
  if (!IsHandleLiveLocked(handle)) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine handle is invalid or already destroyed");
  }
  *out_impl = reinterpret_cast<engine_handle_s*>(handle);
  return ENGINE_RESULT_OK;
}

void SetHandleErrorLocked(engine_handle_s* impl, const char* message) {
  impl->last_error = (message != nullptr) ? message : "";
}

engine_result_t SetHandleErrorAndReturnLocked(engine_handle_s* impl,
                                              engine_result_t result,
                                              const char* message) {
  SetHandleErrorLocked(impl, message);
  return result;
}

engine_result_t ValidateHandleThreadLocked(engine_handle_s* impl) {
  if (impl->owner_thread != std::this_thread::get_id()) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "engine handle must be used on the thread where engine_create was called");
  }
  return ENGINE_RESULT_OK;
}

void ClearHandleErrorLocked(engine_handle_s* impl) {
  impl->last_error.clear();
}

bool EnsureHostCocosRuntimeInitialized() {
  if (g_cocos_bootstrapped) {
    return true;
  }
  if (!g_host_app_delegate) {
    g_host_app_delegate = std::make_unique<TVPAppDelegate>();
  }
  if (!g_host_app_delegate->bootstrapForHostRuntime()) {
    return false;
  }
  g_cocos_bootstrapped = true;
  return true;
}

}  // namespace

extern "C" {

engine_result_t engine_get_runtime_api_version(uint32_t* out_api_version) {
  if (out_api_version == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "out_api_version is null");
  }
  *out_api_version = ENGINE_API_VERSION;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_create(const engine_create_desc_t* desc,
                              engine_handle_t* out_handle) {
  if (desc == nullptr || out_handle == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine_create requires non-null desc and out_handle");
  }

  if (desc->struct_size < sizeof(engine_create_desc_t)) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine_create_desc_t.struct_size is too small");
  }

  const uint32_t expected_major = (ENGINE_API_VERSION >> 24u) & 0xFFu;
  const uint32_t caller_major = (desc->api_version >> 24u) & 0xFFu;
  if (caller_major != expected_major) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_NOT_SUPPORTED,
                                   "unsupported engine API major version");
  }

  EnsureRuntimeLoggersInitialized();
  TVPHostSuppressProcessExit = true;

  auto* impl = new (std::nothrow) engine_handle_s();
  if (impl == nullptr) {
    *out_handle = nullptr;
    return SetThreadErrorAndReturn(ENGINE_RESULT_INTERNAL_ERROR,
                                   "failed to allocate engine handle");
  }

  impl->state = ToStateValue(EngineState::kCreated);
  impl->owner_thread = std::this_thread::get_id();
  impl->runtime_owner = false;

  auto handle = reinterpret_cast<engine_handle_t>(impl);
  {
    std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
    g_live_handles.insert(handle);
  }

  *out_handle = handle;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_destroy(engine_handle_t handle) {
  if (handle == nullptr) {
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }

  engine_handle_s* impl = nullptr;
  bool owned_runtime = false;

  {
    std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
    auto result = ValidateHandleLocked(handle, &impl);
    if (result != ENGINE_RESULT_OK) {
      return result;
    }

    std::lock_guard<std::mutex> guard(impl->mutex);
    result = ValidateHandleThreadLocked(impl);
    if (result != ENGINE_RESULT_OK) {
      return result;
    }

    owned_runtime = (g_runtime_active && g_runtime_owner == handle);
    if (owned_runtime) {
      g_runtime_active = false;
      g_runtime_owner = nullptr;
      impl->runtime_owner = false;
    }

    impl->state = ToStateValue(EngineState::kDestroyed);
    ClearHandleErrorLocked(impl);
    g_live_handles.erase(handle);
  }

  if (owned_runtime) {
    try {
      Application->OnDeactivate();
    } catch (...) {
    }
    Application->FilterUserMessage(
        [](std::vector<std::tuple<void*, int, tTVPApplication::tMsg>>& queue) {
          queue.clear();
        });

    // Avoid triggering platform exit() path in the host process.
    TVPTerminated = false;
    TVPTerminateCode = 0;
  }

  delete impl;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_open_game(engine_handle_t handle,
                                 const char* game_root_path_utf8,
                                 const char* startup_script_utf8) {
  (void)startup_script_utf8;

  if (game_root_path_utf8 == nullptr || game_root_path_utf8[0] == '\0') {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "game_root_path_utf8 is null or empty");
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  result = ValidateHandleThreadLocked(impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  if (impl->state == ToStateValue(EngineState::kDestroyed)) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INVALID_STATE,
                                         "engine is already destroyed");
  }

  if (g_runtime_active) {
    if (g_runtime_owner != handle) {
      return SetHandleErrorAndReturnLocked(
          impl,
          ENGINE_RESULT_INVALID_STATE,
          "runtime is already active on another engine handle");
    }

    impl->state = ToStateValue(EngineState::kOpened);
    ClearHandleErrorLocked(impl);
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }

  if (g_runtime_started_once) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_NOT_SUPPORTED,
        "runtime restart is not supported yet; restart process to open another game");
  }

  TVPTerminated = false;
  TVPTerminateCode = 0;
  TVPSystemUninitCalled = false;
  TVPTerminateOnWindowClose = false;
  TVPTerminateOnNoWindowStartup = false;
  TVPHostSuppressProcessExit = true;

  if (!EnsureHostCocosRuntimeInitialized()) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INTERNAL_ERROR,
        "failed to initialize cocos runtime for host mode");
  }

  try {
    EnsureRuntimeLoggersInitialized();
    Application->StartApplication(ttstr(game_root_path_utf8));
  } catch (...) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INTERNAL_ERROR,
                                         "StartApplication threw an exception");
  }

  if (TVPTerminated) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "runtime requested termination during startup");
  }

  g_runtime_active = true;
  g_runtime_owner = handle;
  g_runtime_started_once = true;

  impl->runtime_owner = true;
  impl->state = ToStateValue(EngineState::kOpened);
  ClearHandleErrorLocked(impl);
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_tick(engine_handle_t handle, uint32_t delta_ms) {
  (void)delta_ms;

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  result = ValidateHandleThreadLocked(impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  if (!g_runtime_active || g_runtime_owner != handle) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "engine_open_game must succeed before engine_tick");
  }

  if (impl->state == ToStateValue(EngineState::kPaused)) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INVALID_STATE,
                                         "engine is paused");
  }

  if (impl->state != ToStateValue(EngineState::kOpened)) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INVALID_STATE,
                                         "engine is not in opened state");
  }

  if (TVPTerminated) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "runtime has been terminated");
  }

  Application->Run();

  if (TVPTerminated) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "runtime requested termination");
  }

  ClearHandleErrorLocked(impl);
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_pause(engine_handle_t handle) {
  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  result = ValidateHandleThreadLocked(impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  if (!g_runtime_active || g_runtime_owner != handle) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "engine_open_game must succeed before engine_pause");
  }

  if (impl->state == ToStateValue(EngineState::kPaused)) {
    ClearHandleErrorLocked(impl);
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }

  if (impl->state != ToStateValue(EngineState::kOpened)) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INVALID_STATE,
                                         "engine_pause requires opened state");
  }

  Application->OnDeactivate();
  impl->state = ToStateValue(EngineState::kPaused);
  ClearHandleErrorLocked(impl);
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_resume(engine_handle_t handle) {
  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  result = ValidateHandleThreadLocked(impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  if (!g_runtime_active || g_runtime_owner != handle) {
    return SetHandleErrorAndReturnLocked(
        impl,
        ENGINE_RESULT_INVALID_STATE,
        "engine_open_game must succeed before engine_resume");
  }

  if (impl->state == ToStateValue(EngineState::kOpened)) {
    ClearHandleErrorLocked(impl);
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }

  if (impl->state != ToStateValue(EngineState::kPaused)) {
    return SetHandleErrorAndReturnLocked(impl, ENGINE_RESULT_INVALID_STATE,
                                         "engine_resume requires paused state");
  }

  Application->OnActivate();
  impl->state = ToStateValue(EngineState::kOpened);
  ClearHandleErrorLocked(impl);
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_set_option(engine_handle_t handle,
                                  const engine_option_t* option) {
  if (option == nullptr || option->key_utf8 == nullptr || option->key_utf8[0] == '\0') {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "option and option->key_utf8 must be non-null/non-empty");
  }
  if (option->value_utf8 == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "option->value_utf8 must be non-null");
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  result = ValidateHandleThreadLocked(impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  TVPSetCommandLine(ttstr(option->key_utf8).c_str(), ttstr(option->value_utf8));

  ClearHandleErrorLocked(impl);
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

const char* engine_get_last_error(engine_handle_t handle) {
  if (handle == nullptr) {
    return g_thread_error.c_str();
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  if (!IsHandleLiveLocked(handle)) {
    SetThreadError("engine handle is invalid or already destroyed");
    return g_thread_error.c_str();
  }
  auto* impl = reinterpret_cast<engine_handle_s*>(handle);
  std::lock_guard<std::mutex> guard(impl->mutex);
  return impl->last_error.c_str();
}

}  // extern "C"

#else

#include <new>
#include <string>
#include <unordered_set>
#include <mutex>

struct engine_handle_s {
  std::mutex mutex;
  std::string last_error;
  int state = 0;
};

namespace {

enum class EngineState {
  kCreated = 0,
  kOpened,
  kPaused,
  kDestroyed,
};

inline int ToStateValue(EngineState state) {
  return static_cast<int>(state);
}

std::mutex g_registry_mutex;
std::unordered_set<engine_handle_t> g_live_handles;
thread_local std::string g_thread_error;

void SetThreadError(const char* message) {
  g_thread_error = (message != nullptr) ? message : "";
}

engine_result_t SetThreadErrorAndReturn(engine_result_t result,
                                        const char* message) {
  SetThreadError(message);
  return result;
}

bool IsHandleLiveLocked(engine_handle_t handle) {
  return g_live_handles.find(handle) != g_live_handles.end();
}

engine_result_t ValidateHandleLocked(engine_handle_t handle,
                                     engine_handle_s** out_impl) {
  if (handle == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine handle is null");
  }
  if (!IsHandleLiveLocked(handle)) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine handle is invalid or already destroyed");
  }
  *out_impl = reinterpret_cast<engine_handle_s*>(handle);
  return ENGINE_RESULT_OK;
}

void SetHandleErrorLocked(engine_handle_s* impl, const char* message) {
  impl->last_error = (message != nullptr) ? message : "";
}

}  // namespace

extern "C" {

engine_result_t engine_get_runtime_api_version(uint32_t* out_api_version) {
  if (out_api_version == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "out_api_version is null");
  }
  *out_api_version = ENGINE_API_VERSION;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_create(const engine_create_desc_t* desc,
                              engine_handle_t* out_handle) {
  if (desc == nullptr || out_handle == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine_create requires non-null desc and out_handle");
  }

  if (desc->struct_size < sizeof(engine_create_desc_t)) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "engine_create_desc_t.struct_size is too small");
  }

  const uint32_t expected_major = (ENGINE_API_VERSION >> 24u) & 0xFFu;
  const uint32_t caller_major = (desc->api_version >> 24u) & 0xFFu;
  if (caller_major != expected_major) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_NOT_SUPPORTED,
                                   "unsupported engine API major version");
  }

  auto* impl = new (std::nothrow) engine_handle_s();
  if (impl == nullptr) {
    *out_handle = nullptr;
    return SetThreadErrorAndReturn(ENGINE_RESULT_INTERNAL_ERROR,
                                   "failed to allocate engine handle");
  }
  impl->state = ToStateValue(EngineState::kCreated);

  auto handle = reinterpret_cast<engine_handle_t>(impl);
  {
    std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
    g_live_handles.insert(handle);
  }

  *out_handle = handle;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_destroy(engine_handle_t handle) {
  if (handle == nullptr) {
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }

  engine_handle_s* impl = nullptr;
  {
    std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
    auto it = g_live_handles.find(handle);
    if (it == g_live_handles.end()) {
      return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                     "engine handle is invalid or already destroyed");
    }
    impl = reinterpret_cast<engine_handle_s*>(handle);
    g_live_handles.erase(it);
  }

  {
    std::lock_guard<std::mutex> guard(impl->mutex);
    impl->state = ToStateValue(EngineState::kDestroyed);
    impl->last_error.clear();
  }
  delete impl;
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_open_game(engine_handle_t handle,
                                 const char* game_root_path_utf8,
                                 const char* startup_script_utf8) {
  (void)startup_script_utf8;

  if (game_root_path_utf8 == nullptr || game_root_path_utf8[0] == '\0') {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "game_root_path_utf8 is null or empty");
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  if (impl->state == ToStateValue(EngineState::kDestroyed)) {
    SetHandleErrorLocked(impl, "engine is already destroyed");
    return ENGINE_RESULT_INVALID_STATE;
  }

  impl->state = ToStateValue(EngineState::kOpened);
  impl->last_error.clear();
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_tick(engine_handle_t handle, uint32_t delta_ms) {
  (void)delta_ms;

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  if (impl->state == ToStateValue(EngineState::kPaused)) {
    SetHandleErrorLocked(impl, "engine is paused");
    return ENGINE_RESULT_INVALID_STATE;
  }
  if (impl->state != ToStateValue(EngineState::kOpened)) {
    SetHandleErrorLocked(impl, "engine_open_game must succeed before engine_tick");
    return ENGINE_RESULT_INVALID_STATE;
  }

  impl->last_error.clear();
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_pause(engine_handle_t handle) {
  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  if (impl->state == ToStateValue(EngineState::kPaused)) {
    impl->last_error.clear();
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }
  if (impl->state != ToStateValue(EngineState::kOpened)) {
    SetHandleErrorLocked(impl, "engine_pause requires opened state");
    return ENGINE_RESULT_INVALID_STATE;
  }

  impl->state = ToStateValue(EngineState::kPaused);
  impl->last_error.clear();
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_resume(engine_handle_t handle) {
  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  if (impl->state == ToStateValue(EngineState::kOpened)) {
    impl->last_error.clear();
    SetThreadError(nullptr);
    return ENGINE_RESULT_OK;
  }
  if (impl->state != ToStateValue(EngineState::kPaused)) {
    SetHandleErrorLocked(impl, "engine_resume requires paused state");
    return ENGINE_RESULT_INVALID_STATE;
  }

  impl->state = ToStateValue(EngineState::kOpened);
  impl->last_error.clear();
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

engine_result_t engine_set_option(engine_handle_t handle,
                                  const engine_option_t* option) {
  if (option == nullptr || option->key_utf8 == nullptr || option->key_utf8[0] == '\0') {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "option and option->key_utf8 must be non-null/non-empty");
  }
  if (option->value_utf8 == nullptr) {
    return SetThreadErrorAndReturn(ENGINE_RESULT_INVALID_ARGUMENT,
                                   "option->value_utf8 must be non-null");
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  engine_handle_s* impl = nullptr;
  auto result = ValidateHandleLocked(handle, &impl);
  if (result != ENGINE_RESULT_OK) {
    return result;
  }

  std::lock_guard<std::mutex> guard(impl->mutex);
  if (impl->state == ToStateValue(EngineState::kDestroyed)) {
    SetHandleErrorLocked(impl, "engine is already destroyed");
    return ENGINE_RESULT_INVALID_STATE;
  }

  impl->last_error.clear();
  SetThreadError(nullptr);
  return ENGINE_RESULT_OK;
}

const char* engine_get_last_error(engine_handle_t handle) {
  if (handle == nullptr) {
    return g_thread_error.c_str();
  }

  std::lock_guard<std::mutex> registry_guard(g_registry_mutex);
  if (!IsHandleLiveLocked(handle)) {
    SetThreadError("engine handle is invalid or already destroyed");
    return g_thread_error.c_str();
  }
  auto* impl = reinterpret_cast<engine_handle_s*>(handle);
  std::lock_guard<std::mutex> guard(impl->mutex);
  return impl->last_error.c_str();
}

}  // extern "C"

#endif
