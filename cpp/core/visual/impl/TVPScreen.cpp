#include "tjsCommHead.h"

#include "TVPScreen.h"
#include "Application.h"
#include "krkr_egl_context.h"

int tTVPScreen::GetWidth() { return 2048; }
int tTVPScreen::GetHeight() {
    // Use EGL surface dimensions if available, otherwise fallback to width
    auto& egl = krkr::GetEngineEGLContext();
    if (egl.IsValid()) {
        uint32_t w = egl.GetWidth();
        uint32_t h = egl.GetHeight();
        if (w > 0 && h > 0) {
            int baseW = GetWidth();
            return baseW * static_cast<int>(h) / static_cast<int>(w);
        }
    }
    return GetWidth();
}

int tTVPScreen::GetDesktopLeft() { return 0; }
int tTVPScreen::GetDesktopTop() { return 0; }
int tTVPScreen::GetDesktopWidth() { return GetWidth(); }
int tTVPScreen::GetDesktopHeight() { return GetHeight(); }
