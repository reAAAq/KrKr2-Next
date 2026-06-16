//---------------------------------------------------------------------------
/*
        TVP2 ( T Visual Presenter 2 )  A script authoring tool
        Copyright (C) 2000 W.Dee <dee@kikyou.info> and contributors

        See details of license at "license.txt"
*/
//---------------------------------------------------------------------------
// System Initialization and Uninitialization
//---------------------------------------------------------------------------
#include "tjsCommHead.h"

#include <vector>
#include <algorithm>
#include <functional>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#include "tjsUtils.h"
#include "SysInitIntf.h"
#include "ScriptMgnIntf.h"
#include "tvpgl.h"

//---------------------------------------------------------------------------
// global data
//---------------------------------------------------------------------------
ttstr TVPProjectDir; // project directory (in unified storage name)
ttstr TVPDataPath; // data directory (in unified storage name)
//---------------------------------------------------------------------------

extern void TVPGL_C_Init();

//---------------------------------------------------------------------------
// TVPSystemInit : Entire System Initialization
//---------------------------------------------------------------------------
void TVPSystemInit() {
#ifdef _WIN32
#ifdef USING_PROTECT
    while(!TVPProtectInit()) {
        TVPUpdateLicense();
    }
#endif
#endif

    TVPBeforeSystemInit();

    TVPInitScriptEngine();

    TVPInitTVPGL();
    //	TVPGL_C_Init();

    TVPAfterSystemInit();
}
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
// TVPSystemUninit : System shutdown, cleanup, etc...
//---------------------------------------------------------------------------
static void TVPCauseAtExit();

bool TVPSystemUninitCalled = false;

void TVPSystemUninit() {
    if(TVPSystemUninitCalled)
        return;
    TVPSystemUninitCalled = true;

    TVPBeforeSystemUninit();

    TVPUninitTVPGL();

    try {
        TVPUninitScriptEngine();
    } catch(...) {
        // ignore errors
    }

    TVPAfterSystemUninit();

    TVPCauseAtExit();
}
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
// TVPAddAtExitHandler related
//---------------------------------------------------------------------------
struct tTVPAtExitInfo {
    tTVPAtExitInfo(tjs_int pri, void (*handler)()) {
        Priority = pri, Handler = handler;
    }

    tjs_int Priority;

    void (*Handler)();

    bool operator<(const tTVPAtExitInfo &r) const {
        return this->Priority < r.Priority;
    }

    bool operator>(const tTVPAtExitInfo &r) const {
        return this->Priority > r.Priority;
    }

    bool operator==(const tTVPAtExitInfo &r) const {
        return this->Priority == r.Priority;
    }
};

// At-exit handler storage.
//
// Handlers are registered (almost) exclusively via `static tTVPAtExit X(...)`
// instances scattered across the codebase. C++ static initializers only run
// once per process lifetime, so a "restart" (engine_destroy + engine_init in
// the same process) cannot rely on those re-registering the handlers.
//
// To support arbitrarily many restarts we keep the handler list alive for the
// entire process lifetime via a Meyers' singleton, and merely mark which
// handlers have already been invoked for the current run. On the next
// startup, TVPResetRuntimeForRestart() rearms every handler so they fire
// again on the next shutdown — without re-running any C++ static initializer.
static std::vector<tTVPAtExitInfo> &TVPAtExitInfoList() {
    // Function-local static — constructed on first use, destroyed only at
    // process exit. Avoids static init order fiasco and naturally survives
    // engine_destroy / engine_init cycles.
    static std::vector<tTVPAtExitInfo> infos;
    return infos;
}

static bool TVPAtExitShutdown = false;
static bool TVPAtExitSorted = false;

//---------------------------------------------------------------------------
void TVPAddAtExitHandler(tjs_int pri, void (*handler)()) {
    if(TVPAtExitShutdown)
        return;

    auto &infos = TVPAtExitInfoList();
    infos.emplace_back(pri, handler);
    // A new handler was added — re-sort on next TVPCauseAtExit().
    TVPAtExitSorted = false;
}

//---------------------------------------------------------------------------
static void TVPCauseAtExit() {
    if(TVPAtExitShutdown)
        return;
    TVPAtExitShutdown = true;

    auto &infos = TVPAtExitInfoList();
    if(infos.empty())
        return;

    if(!TVPAtExitSorted) {
        std::sort(infos.begin(), infos.end()); // descending sort
        TVPAtExitSorted = true;
    }

    // Iterate by index; in the unlikely event a handler registers another
    // handler we won't crash on iterator invalidation. The new one will be
    // picked up on the next shutdown after a restart.
    const size_t snapshot = infos.size();
    for(size_t i = 0; i < snapshot; ++i) {
        infos[i].Handler();
    }
}
//---------------------------------------------------------------------------

//---------------------------------------------------------------------------
// TVPResetRuntimeForRestart : Reset state to allow re-initialization
//---------------------------------------------------------------------------
void TVPResetRuntimeForRestart() {
    TVPSystemUninitCalled = false;
    // Re-arm all at-exit handlers. The handler list itself is preserved by
    // TVPAtExitInfoList()'s function-local static; we only need to flip the
    // shutdown flag so TVPCauseAtExit() will run them again on next teardown.
    TVPAtExitShutdown = false;
    TVPProjectDir.Clear();
    TVPDataPath.Clear();
}
//---------------------------------------------------------------------------
