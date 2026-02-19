/**
 * @file MainScene.cpp
 * @brief Stub MainScene implementation — no Cocos2d-x dependency.
 *
 * This replaces the 2700-line Cocos2d-x MainScene with a minimal engine
 * loop driver.  The original code mixed UI management (pushUIForm/popUIForm),
 * input handling (touch/keyboard/controller), window layer management,
 * cursor rendering, and the core Application::Run() loop.
 *
 * In the new architecture:
 *   - UI is handled by Flutter (host side)
 *   - Input is forwarded via engine_api → EngineLoop (TODO Phase 4)
 *   - This file only retains the core loop: Application::Run() per frame
 */

#include "MainScene.h"

#include <spdlog/spdlog.h>
#include <thread>

#include "Application.h"
#include "ConfigManager/IndividualConfigManager.h"
#include "ConfigManager/GlobalConfigManager.h"
#include "Platform.h"
#include "SysInitIntf.h"
#include "RenderManager.h"
#include "TickCount.h"

// Forward declarations for functions used by the engine core
extern bool TVPCheckStartupPath(const std::string &path);

// ---------------------------------------------------------------------------
// Global state previously in MainScene.cpp
// ---------------------------------------------------------------------------

static void (*_postUpdate)() = nullptr;
void TVPSetPostUpdateEvent(void (*f)()) { _postUpdate = f; }

static tjs_uint8 _scancode[0x200] = {};
bool TVPGetKeyMouseAsyncState(tjs_uint keycode, bool getcurrent) {
    if (keycode >= sizeof(_scancode) / sizeof(_scancode[0]))
        return false;
    tjs_uint8 code = _scancode[keycode];
    _scancode[keycode] &= 1;
    return code & (getcurrent ? 1 : 0x10);
}

bool TVPGetJoyPadAsyncState(tjs_uint keycode, bool getcurrent) {
    if (keycode >= sizeof(_scancode) / sizeof(_scancode[0]))
        return false;
    tjs_uint8 code = _scancode[keycode];
    _scancode[keycode] &= 1;
    return code & (getcurrent ? 1 : 0x10);
}

void TVPForceSwapBuffer();

int TVPDrawSceneOnce(int interval) {
    static tjs_uint64 lastTick = TVPGetRoughTickCount32();
    tjs_uint64 curTick = TVPGetRoughTickCount32();
    int remain = interval - static_cast<int>(curTick - lastTick);
    if (remain <= 0) {
        if (_postUpdate)
            _postUpdate();
        // In the original code, this called Director::drawScene() +
        // TVPForceSwapBuffer(). Now we just do the swap (ANGLE eglSwapBuffers
        // or no-op in Pbuffer mode).
        TVPForceSwapBuffer();
        lastTick = curTick;
        return 0;
    } else {
        return remain;
    }
}

// ---------------------------------------------------------------------------
// TVPMainScene implementation
// ---------------------------------------------------------------------------

static TVPMainScene *_instance = nullptr;

TVPMainScene::TVPMainScene() = default;
TVPMainScene::~TVPMainScene() {
    if (_instance == this) {
        _instance = nullptr;
    }
}

TVPMainScene *TVPMainScene::GetInstance() { return _instance; }

TVPMainScene *TVPMainScene::CreateInstance() {
    if (!_instance) {
        _instance = new TVPMainScene();
    }
    return _instance;
}

void TVPMainScene::scheduleUpdate() {
    _updateScheduled = true;
}

void TVPMainScene::update(float delta) {
    if (!_started)
        return;
    ::Application->Run();
    iTVPTexture2D::RecycleProcess();
    if (_postUpdate)
        _postUpdate();
}

bool TVPMainScene::startupFrom(const std::string &path) {
    if (!TVPCheckStartupPath(path)) {
        return false;
    }

    IndividualConfigManager *pCfgMgr = IndividualConfigManager::GetInstance();
    // Use preference at game directory
    // (path splitting logic preserved from original)
    auto sepPos = path.find_last_of("/\\");
    if (sepPos != std::string::npos) {
        pCfgMgr->UsePreferenceAt(path.substr(0, sepPos));
    }

    doStartup(path);
    return true;
}

void TVPMainScene::doStartup(const std::string &path) {
    spdlog::info("TVPMainScene::doStartup starting game from: {}", path);

    ::Application->StartApplication(path);

    // Run one frame immediately (matches original behavior)
    update(0);

    _started = true;
    _updateScheduled = true;

    spdlog::info("TVPMainScene::doStartup complete");
}
