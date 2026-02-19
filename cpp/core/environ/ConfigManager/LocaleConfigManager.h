// multi language config mainly for ui
#pragma once
#include <unordered_map>
#include <string>
#include <vector>


class LocaleConfigManager {

    std::unordered_map<std::string, std::string> AllConfig; // tid->text in utf8

    bool ConfigUpdated{};

    LocaleConfigManager();

    std::string GetFilePath();

public:
    static LocaleConfigManager *GetInstance();

    void Initialize(const std::string &sysLang);

    const std::string &GetText(const std::string &tid); // in utf8

private:
    std::string currentLangCode;
};