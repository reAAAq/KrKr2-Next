#include "LocaleConfigManager.h"
#include "GlobalConfigManager.h"
#include <tinyxml2.h>

#include <filesystem>
#include <fstream>
#include <sstream>
#include <spdlog/spdlog.h>

LocaleConfigManager::LocaleConfigManager() = default;

// Helper: check if a file exists using std::filesystem
static bool FileExists(const std::string &path) {
    std::error_code ec;
    return std::filesystem::exists(path, ec);
}

// Helper: read entire file to string
static std::string ReadFileToString(const std::string &path) {
    std::ifstream ifs(path, std::ios::binary);
    if (!ifs.is_open()) return "";
    std::ostringstream ss;
    ss << ifs.rdbuf();
    return ss.str();
}

std::string LocaleConfigManager::GetFilePath() {
    constexpr const char *kPathPrefix = "locale/";
    const std::string requested = std::string(kPathPrefix) + currentLangCode + ".xml";
    if (FileExists(requested)) {
        return requested;
    }

    // Fallback to default locale once.
    const std::string fallback = std::string(kPathPrefix) + "en_us.xml";
    if (FileExists(fallback)) {
        currentLangCode = "en_us";
        return fallback;
    }

    return "";
}

LocaleConfigManager *LocaleConfigManager::GetInstance() {
    static LocaleConfigManager instance;
    return &instance;
}

const std::string &LocaleConfigManager::GetText(const std::string &tid) {
    auto it = AllConfig.find(tid);
    if (it == AllConfig.end()) {
        AllConfig[tid] = tid;
        return AllConfig[tid];
    }
    return it->second;
}

void LocaleConfigManager::Initialize(const std::string &sysLang) {
    // override by global configured lang
    currentLangCode = GlobalConfigManager::GetInstance()->GetValue<std::string>(
        "user_language", "");
    if (currentLangCode.empty())
        currentLangCode = sysLang;
    AllConfig.clear();
    AllConfig.reserve(128);
    tinyxml2::XMLDocument doc;
    const std::string filePath = GetFilePath();
    if (filePath.empty()) {
        // Keep map empty and fall back to key-as-text in GetText().
        return;
    }
    std::string xmlData = ReadFileToString(filePath);
    if (xmlData.empty()) {
        return;
    }
    doc.Parse(xmlData.c_str(), xmlData.size());
    tinyxml2::XMLElement *rootElement = doc.RootElement();
    if (rootElement) {
        for (tinyxml2::XMLElement *item = rootElement->FirstChildElement(); item;
             item = item->NextSiblingElement()) {
            const char *key = item->Attribute("id");
            const char *val = item->Attribute("text");
            if (key && val) {
                AllConfig[key] = val;
            }
        }
    }
}
