#include "LogSetup.h"

#include <spdlog/logger.h>
#include <spdlog/spdlog.h>

namespace {

constexpr const char *kTVPLogPattern =
    "[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] [%n] [%@] %v";

}

void TVPConfigureLoggerPattern(const std::shared_ptr<spdlog::logger> &logger) {
    if(logger) {
        logger->set_pattern(kTVPLogPattern);
    }
}

void TVPConfigureDefaultLoggerPattern() {
    TVPConfigureLoggerPattern(spdlog::default_logger());
}
