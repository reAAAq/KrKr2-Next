/**
 * @file ui_stubs.cpp
 * @brief Stub implementations for UI layer functions and platform
 *        functions that were previously provided by MainScene.cpp,
 *        AppDelegate.cpp, and the environ/ui/ directory.
 *
 * With the migration to Flutter-based UI, all of these are replaced by
 * minimal stubs that either log a warning or return a sensible default.
 *
 * Functions stubbed here are called from the engine core and must link,
 * but their functionality will be provided by the Flutter host layer.
 */

#include <spdlog/spdlog.h>
#include <string>
#include <vector>
#include <filesystem>

#include "tjsCommHead.h"
#include "tjsConfig.h"
#include "WindowIntf.h"
#include "MenuItemIntf.h"
#include "Platform.h"

// Forward declarations
class iWindowLayer;

// ---------------------------------------------------------------------------
// TVPInitUIExtension — originally in ui/extension/UIExtension.cpp
// Registered custom UI widgets (PageView, etc.)
// ---------------------------------------------------------------------------
void TVPInitUIExtension() {
    spdlog::debug("TVPInitUIExtension: stub (UI handled by Flutter)");
}

// ---------------------------------------------------------------------------
// TVPCreateAndAddWindow — originally in MainScene.cpp
// Creates a window layer and adds it to the scene tree. In Flutter mode,
// the window is a logical entity; rendering goes through glReadPixels.
// ---------------------------------------------------------------------------
iWindowLayer *TVPCreateAndAddWindow(tTJSNI_Window *w) {
    spdlog::warn("TVPCreateAndAddWindow: stub — window creation handled by Flutter");
    return nullptr;
}

// ---------------------------------------------------------------------------
// TVPConsoleLog — originally in MainScene.cpp
// Logs engine console output. Redirect to spdlog.
// ---------------------------------------------------------------------------
void TVPConsoleLog(const ttstr &mes, bool important) {
    // Convert TJS string to UTF-8 for spdlog
    tTJSNarrowStringHolder narrow_mes(mes.c_str());
    if (important) {
        spdlog::info("[TVP Console] {}", narrow_mes.operator const char *());
    } else {
        spdlog::debug("[TVP Console] {}", narrow_mes.operator const char *());
    }
}

// ---------------------------------------------------------------------------
// TJS::TVPConsoleLog — originally in MainScene.cpp (TJS2 namespace version)
// ---------------------------------------------------------------------------
namespace TJS {
void TVPConsoleLog(const tTJSString &str) {
    tTJSNarrowStringHolder narrow(str.c_str());
    spdlog::debug("[TJS Console] {}", narrow.operator const char *());
}
} // namespace TJS

// ---------------------------------------------------------------------------
// TVPGetOSName / TVPGetPlatformName — originally in MainScene.cpp
// Returns OS/platform identification strings.
// ---------------------------------------------------------------------------
ttstr TVPGetOSName() {
#if defined(__APPLE__)
    return ttstr(TJS_W("macOS"));
#elif defined(_WIN32)
    return ttstr(TJS_W("Windows"));
#elif defined(__linux__)
    return ttstr(TJS_W("Linux"));
#else
    return ttstr(TJS_W("Unknown"));
#endif
}

ttstr TVPGetPlatformName() {
#if defined(__aarch64__) || defined(_M_ARM64)
    return ttstr(TJS_W("ARM64"));
#elif defined(__x86_64__) || defined(_M_X64)
    return ttstr(TJS_W("x86_64"));
#else
    return ttstr(TJS_W("Unknown"));
#endif
}

// ---------------------------------------------------------------------------
// TVPGetInternalPreferencePath — originally in MainScene.cpp
// Returns the directory path for storing preferences/config files.
// ---------------------------------------------------------------------------
static std::string s_internalPreferencePath;

const std::string &TVPGetInternalPreferencePath() {
    if (s_internalPreferencePath.empty()) {
#if defined(__APPLE__)
        const char *home = getenv("HOME");
        if (home) {
            s_internalPreferencePath = std::string(home) + "/Library/Application Support/krkr2/";
        } else {
            s_internalPreferencePath = "/tmp/krkr2/";
        }
#else
        s_internalPreferencePath = "/tmp/krkr2/";
#endif
        std::filesystem::create_directories(s_internalPreferencePath);
    }
    return s_internalPreferencePath;
}

// ---------------------------------------------------------------------------
// TVPGetApplicationHomeDirectory — originally in MainScene.cpp
// Returns list of directories where the application searches for data files.
// ---------------------------------------------------------------------------
static std::vector<std::string> s_appHomeDirs;

const std::vector<std::string> &TVPGetApplicationHomeDirectory() {
    if (s_appHomeDirs.empty()) {
        // Use current working directory as default
        s_appHomeDirs.push_back(std::filesystem::current_path().string() + "/");
    }
    return s_appHomeDirs;
}

// ---------------------------------------------------------------------------
// TVPCopyFile — originally in CustomFileUtils.cpp
// Copies a file from source to destination.
// ---------------------------------------------------------------------------
bool TVPCopyFile(const std::string &from, const std::string &to) {
    std::error_code ec;
    std::filesystem::copy_file(from, to,
        std::filesystem::copy_options::overwrite_existing, ec);
    if (ec) {
        spdlog::error("TVPCopyFile failed: {} -> {} ({})", from, to, ec.message());
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// TVPShowFileSelector — originally in ui/FileSelectorForm.cpp
// Shows a file selection dialog. In Flutter mode, this is handled by the
// Flutter host layer. Returns empty string (no selection).
// ---------------------------------------------------------------------------
std::string TVPShowFileSelector(const std::string &title,
                                const std::string &init_dir,
                                std::string default_ext,
                                bool is_save) {
    spdlog::warn("TVPShowFileSelector: stub — file selection handled by Flutter");
    return "";
}

// ---------------------------------------------------------------------------
// TVPShowPopMenu — originally in ui/InGameMenuForm.cpp
// Shows a popup context menu. In Flutter mode, handled by Flutter host.
// ---------------------------------------------------------------------------
void TVPShowPopMenu(tTJSNI_MenuItem *menu) {
    spdlog::warn("TVPShowPopMenu: stub — popup menus handled by Flutter");
}

// ---------------------------------------------------------------------------
// TVPOpenPatchLibUrl — originally in AppDelegate.cpp
// Opens the URL for the patch library website.
// ---------------------------------------------------------------------------
void TVPOpenPatchLibUrl() {
    spdlog::warn("TVPOpenPatchLibUrl: stub — URL opening handled by Flutter");
}
