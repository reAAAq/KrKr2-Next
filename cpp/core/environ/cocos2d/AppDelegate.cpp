#include <spdlog/spdlog.h>
#include "AppDelegate.h"

#include "MainScene.h"
#include "Application.h"
#include "Platform.h"
#include "ui/GlobalPreferenceForm.h"
#include "ui/MainFileSelectorForm.h"
#include "ui/extension/UIExtension.h"
#include "ConfigManager/LocaleConfigManager.h"

static cocos2d::Size designSize(960, 640);
extern std::thread::id TVPMainThreadID;

extern "C" void SDL_SetMainReady();

bool TVPCheckStartupArg();

std::string TVPGetCurrentLanguage();

namespace {

bool SetupRuntime(bool scheduleStandaloneStartupUi) {
    SDL_SetMainReady();
    TVPMainThreadID = std::this_thread::get_id();
    spdlog::debug("App Finish Launching");
    auto director = cocos2d::Director::getInstance();
    auto glview = director->getOpenGLView();
    if(!glview) {
        glview = cocos2d::GLViewImpl::create("krkr2");
        director->setOpenGLView(glview);
#if CC_TARGET_PLATFORM == CC_PLATFORM_WIN32
        HWND hwnd = glview->getWin32Window();
        if(hwnd) {
            LONG style = GetWindowLong(hwnd, GWL_STYLE);
            style |= WS_THICKFRAME | WS_MAXIMIZEBOX;
            SetWindowLong(hwnd, GWL_STYLE, style);
        }
#endif
    }

#if (CC_TARGET_PLATFORM == CC_PLATFORM_ANDROID ||                              \
     CC_TARGET_PLATFORM == CC_PLATFORM_IOS)
    cocos2d::Size screenSize = glview->getFrameSize();
    if(screenSize.width < screenSize.height) {
        std::swap(screenSize.width, screenSize.height);
    }
    cocos2d::Size ds = designSize;
    ds.height = ds.width * screenSize.height / screenSize.width;
    glview->setDesignResolutionSize(screenSize.width, screenSize.height,
                                    ResolutionPolicy::EXACT_FIT);
#else
    glview->setDesignResolutionSize(designSize.width, designSize.height,
                                    ResolutionPolicy::FIXED_WIDTH);
#endif

    std::vector<std::string> searchPath;
    searchPath.emplace_back("res");
    cocos2d::FileUtils::getInstance()->setSearchPaths(searchPath);

    director->setDisplayStats(false);
    director->setAnimationInterval(1.0f / 60);

    TVPInitUIExtension();
    LocaleConfigManager::GetInstance()->Initialize(TVPGetCurrentLanguage());

    auto *scene = TVPMainScene::GetInstance();
    if(scene == nullptr) {
        scene = TVPMainScene::CreateInstance();
    }
    if(director->getRunningScene() == nullptr) {
        director->runWithScene(scene);
    }

    if(scheduleStandaloneStartupUi && scene != nullptr) {
        scene->scheduleOnce(
            [](float dt) {
                TVPMainScene::GetInstance()->unschedule("launch");
                TVPGlobalPreferenceForm::Initialize();
                if(!TVPCheckStartupArg()) {
                    TVPMainScene::GetInstance()->pushUIForm(
                        TVPMainFileSelectorForm::create());
                }
            },
            0, "launch");
    }

    return true;
}

} // namespace

void TVPAppDelegate::applicationWillEnterForeground() {
    ::Application->OnActivate();
    cocos2d::Director::getInstance()->startAnimation();
}

void TVPAppDelegate::applicationDidEnterBackground() {
    ::Application->OnDeactivate();
    cocos2d::Director::getInstance()->stopAnimation();
}

bool TVPAppDelegate::applicationDidFinishLaunching() {
    return SetupRuntime(true);
}

bool TVPAppDelegate::bootstrapForHostRuntime() { return SetupRuntime(false); }

void TVPAppDelegate::initGLContextAttrs() {
    GLContextAttrs glContextAttrs = { 8, 8, 8, 8, 24, 8 };
    cocos2d::GLView::setGLContextAttrs(glContextAttrs);
}


void TVPOpenPatchLibUrl() {
    cocos2d::Application::getInstance()->openURL(
        "https://zeas2.github.io/Kirikiroid2_patch/patch");
}
