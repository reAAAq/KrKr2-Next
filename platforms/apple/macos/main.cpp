#include <memory>

#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>

#include "environ/EngineBootstrap.h"
#include "environ/Application.h"

int main(int argc, char *argv[]) {
    spdlog::set_level(spdlog::level::debug);

    static auto core_logger = spdlog::stdout_color_mt("core");
    static auto tjs2_logger = spdlog::stdout_color_mt("tjs2");
    static auto plugin_logger = spdlog::stdout_color_mt("plugin");

    spdlog::set_default_logger(core_logger);

    // Initialize the engine with a default 960x640 surface
    if (!TVPEngineBootstrap::Initialize(960, 640)) {
        spdlog::error("Failed to initialize engine bootstrap");
        return 1;
    }

    // Run the application main loop
    extern class tTVPApplication *Application;
    if (Application) {
        Application->Run();
    }

    TVPEngineBootstrap::Shutdown();
    return 0;
}
