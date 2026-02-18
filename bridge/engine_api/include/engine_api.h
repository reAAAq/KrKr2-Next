#ifndef KRKR2_ENGINE_API_H_
#define KRKR2_ENGINE_API_H_

#include <stddef.h>
#include <stdint.h>

/* Export macro for shared-library builds. */
#if defined(_WIN32)
#if defined(ENGINE_API_BUILD_SHARED)
#define ENGINE_API_EXPORT __declspec(dllexport)
#elif defined(ENGINE_API_USE_SHARED)
#define ENGINE_API_EXPORT __declspec(dllimport)
#else
#define ENGINE_API_EXPORT
#endif
#else
#if defined(__GNUC__) && __GNUC__ >= 4
#define ENGINE_API_EXPORT __attribute__((visibility("default")))
#else
#define ENGINE_API_EXPORT
#endif
#endif

#if defined(__cplusplus)
extern "C" {
#endif

/* ABI version: major(8bit), minor(8bit), patch(16bit). */
#define ENGINE_API_VERSION 0x01000000u
#define ENGINE_API_MAKE_VERSION(major, minor, patch) \
  ((((uint32_t)(major)&0xFFu) << 24u) | (((uint32_t)(minor)&0xFFu) << 16u) | \
   ((uint32_t)(patch)&0xFFFFu))

typedef struct engine_handle_s* engine_handle_t;

typedef enum engine_result_t {
  ENGINE_RESULT_OK = 0,
  ENGINE_RESULT_INVALID_ARGUMENT = -1,
  ENGINE_RESULT_INVALID_STATE = -2,
  ENGINE_RESULT_NOT_SUPPORTED = -3,
  ENGINE_RESULT_IO_ERROR = -4,
  ENGINE_RESULT_INTERNAL_ERROR = -5
} engine_result_t;

typedef struct engine_create_desc_t {
  uint32_t struct_size;
  uint32_t api_version;
  const char* writable_path_utf8;
  const char* cache_path_utf8;
  void* user_data;
  uint64_t reserved_u64[4];
  void* reserved_ptr[4];
} engine_create_desc_t;

typedef struct engine_option_t {
  const char* key_utf8;
  const char* value_utf8;
  uint64_t reserved_u64[2];
  void* reserved_ptr[2];
} engine_option_t;

/*
 * Returns runtime API version in out_api_version.
 * out_api_version must be non-null.
 */
ENGINE_API_EXPORT engine_result_t engine_get_runtime_api_version(
    uint32_t* out_api_version);

/*
 * Creates an engine handle.
 * desc and out_handle must be non-null.
 * out_handle is set only when ENGINE_RESULT_OK is returned.
 */
ENGINE_API_EXPORT engine_result_t engine_create(const engine_create_desc_t* desc,
                                                engine_handle_t* out_handle);

/*
 * Destroys engine handle and releases all resources.
 * Idempotent: passing a null handle returns ENGINE_RESULT_OK.
 */
ENGINE_API_EXPORT engine_result_t engine_destroy(engine_handle_t handle);

/*
 * Opens a game package/root directory.
 * handle and game_root_path_utf8 must be non-null.
 * startup_script_utf8 may be null to use default startup script.
 */
ENGINE_API_EXPORT engine_result_t engine_open_game(
    engine_handle_t handle, const char* game_root_path_utf8,
    const char* startup_script_utf8);

/*
 * Ticks engine main loop once.
 * handle must be non-null.
 * delta_ms is caller-provided elapsed milliseconds.
 */
ENGINE_API_EXPORT engine_result_t engine_tick(engine_handle_t handle,
                                              uint32_t delta_ms);

/*
 * Pauses runtime execution.
 * Idempotent: calling pause on a paused engine returns ENGINE_RESULT_OK.
 */
ENGINE_API_EXPORT engine_result_t engine_pause(engine_handle_t handle);

/*
 * Resumes runtime execution.
 * Idempotent: calling resume on a running engine returns ENGINE_RESULT_OK.
 */
ENGINE_API_EXPORT engine_result_t engine_resume(engine_handle_t handle);

/*
 * Sets runtime option by UTF-8 key/value pair.
 * handle and option must be non-null.
 */
ENGINE_API_EXPORT engine_result_t engine_set_option(engine_handle_t handle,
                                                    const engine_option_t* option);

/*
 * Returns last error message as UTF-8 null-terminated string.
 * The returned pointer remains valid until next API call on the same handle.
 * Returns empty string when no error is recorded.
 */
ENGINE_API_EXPORT const char* engine_get_last_error(engine_handle_t handle);

#if defined(__cplusplus)
}  /* extern "C" */
#endif

#endif  /* KRKR2_ENGINE_API_H_ */
