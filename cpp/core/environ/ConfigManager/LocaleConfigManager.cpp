#include "LocaleConfigManager.h"
#include "platform/CCFileUtils.h"
#include "GlobalConfigManager.h"
#include "tinyxml2/tinyxml2.h"
#include "ui/UIText.h"
#include "ui/UIButton.h"

LocaleConfigManager::LocaleConfigManager() = default;

std::string LocaleConfigManager::GetFilePath() {
    constexpr const char *kPathPrefix = "locale/";
    const std::string requested = std::string(kPathPrefix) + currentLangCode + ".xml";
    if(cocos2d::FileUtils::getInstance()->isFileExist(requested)) {
        return cocos2d::FileUtils::getInstance()->fullPathForFilename(requested);
    }

    // Fallback to default locale once. If still missing, return empty path
    // to avoid recursive lookup and let callers safely degrade.
    const std::string fallback = std::string(kPathPrefix) + "en_us.xml";
    if(cocos2d::FileUtils::getInstance()->isFileExist(fallback)) {
        currentLangCode = "en_us";
        return cocos2d::FileUtils::getInstance()->fullPathForFilename(fallback);
    }

    return "";
}

LocaleConfigManager *LocaleConfigManager::GetInstance() {
    static LocaleConfigManager instance;
    return &instance;
}

const std::string &LocaleConfigManager::GetText(const std::string &tid) {
    auto it = AllConfig.find(tid);
    if(it == AllConfig.end()) {
        AllConfig[tid] = tid;
        return AllConfig[tid];
    }
    return it->second;
}

void LocaleConfigManager::Initialize(const std::string &sysLang) {
    // override by global configured lang
    currentLangCode = GlobalConfigManager::GetInstance()->GetValue<std::string>(
        "user_language", "");
    if(currentLangCode.empty())
        currentLangCode = sysLang;
    AllConfig.clear();
    AllConfig.reserve(128);
    tinyxml2::XMLDocument doc;
    const std::string filePath = GetFilePath();
    if(filePath.empty()) {
        // Keep map empty and fall back to key-as-text in GetText().
        return;
    }
    std::string xmlData = cocos2d::FileUtils::getInstance()->getStringFromFile(filePath);
    if(xmlData.empty()) {
        return;
    }
    bool _writeBOM = false;
    const char *p = xmlData.c_str();
    p = tinyxml2::XMLUtil::ReadBOM(p, &_writeBOM);
    doc.ParseDeep((char *)p, nullptr);
    tinyxml2::XMLElement *rootElement = doc.RootElement();
    if(rootElement) {
        for(tinyxml2::XMLElement *item = rootElement->FirstChildElement(); item;
            item = item->NextSiblingElement()) {
            const char *key = item->Attribute("id");
            const char *val = item->Attribute("text");
            if(key && val) {
                AllConfig[key] = val;
            }
        }
    }
}

bool LocaleConfigManager::initText(cocos2d::ui::Text *ctrl) {
    if(!ctrl)
        return false;
    return initText(ctrl, ctrl->getString());
}

bool LocaleConfigManager::initText(cocos2d::ui::Button *ctrl) {
    if(!ctrl)
        return false;
    return initText(ctrl, ctrl->getTitleText());
}

bool LocaleConfigManager::initText(cocos2d::ui::Text *ctrl,
                                   const std::string &tid) {
    if(!ctrl)
        return false;

    std::string txt = GetText(tid);
    if(txt.empty()) {
        ctrl->setString(tid);
        ctrl->setColor(cocos2d::Color3B::RED);
        return false;
    }

    ctrl->setString(txt);
    return true;
}

bool LocaleConfigManager::initText(cocos2d::ui::Button *ctrl,
                                   const std::string &tid) {
    if(!ctrl)
        return false;

    std::string txt = GetText(tid);
    if(txt.empty()) {
        ctrl->setTitleText(tid);
        ctrl->setTitleColor(cocos2d::Color3B::RED);
        return false;
    }

    ctrl->setTitleText(txt);
    return true;
}
