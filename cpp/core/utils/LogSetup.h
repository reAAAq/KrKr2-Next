#pragma once

#include <cstring>
#include <memory>

#include <spdlog/spdlog.h>

namespace spdlog {
class logger;
}

void TVPConfigureLoggerPattern(const std::shared_ptr<spdlog::logger> &logger);
void TVPConfigureDefaultLoggerPattern();

inline const char *TVPRelativeSourceFile(const char *file) {
    if(file == nullptr)
        return "<unknown>";

#ifdef TVP_SOURCE_ROOT
    constexpr char kSourceRoot[] = TVP_SOURCE_ROOT;
    constexpr size_t kSourceRootLen = sizeof(kSourceRoot) - 1;
    if(std::strncmp(file, kSourceRoot, kSourceRootLen) == 0)
        return file + kSourceRootLen;
#endif

    static constexpr const char *kMarkers[] = {
        "cpp/",       "cpp\\",       "bridge/",    "bridge\\",
        "platforms/", "platforms\\", "apps/",      "apps\\",
    };
    for(const char *marker : kMarkers) {
        if(const char *found = std::strstr(file, marker))
            return found;
    }

    return file;
}

#define TVP_SPDLOG_TRACE(...)                                                 \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::trace, __VA_ARGS__)

#define TVP_SPDLOG_DEBUG(...)                                                 \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::debug, __VA_ARGS__)

#define TVP_SPDLOG_INFO(...)                                                  \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::info, __VA_ARGS__)

#define TVP_SPDLOG_WARN(...)                                                  \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::warn, __VA_ARGS__)

#define TVP_SPDLOG_ERROR(...)                                                 \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::err, __VA_ARGS__)

#define TVP_SPDLOG_CRITICAL(...)                                              \
    spdlog::log(spdlog::source_loc{TVPRelativeSourceFile(__FILE__),           \
                                   __LINE__, SPDLOG_FUNCTION},                \
                spdlog::level::critical, __VA_ARGS__)
