/**
 * @file KrkrJniHelper.cpp
 * @brief Lightweight JNI helper implementation — replaces cocos2d::JniHelper.
 */

#ifdef __ANDROID__

#include "KrkrJniHelper.h"
#include <android/log.h>
#include <mutex>

#define LOG_TAG "krkr2"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace krkr {

static JavaVM* g_javaVM = nullptr;
static std::mutex g_jvm_mutex;

void JniHelper::setJavaVM(JavaVM* vm) {
    std::lock_guard<std::mutex> lock(g_jvm_mutex);
    g_javaVM = vm;
}

JavaVM* JniHelper::getJavaVM() {
    std::lock_guard<std::mutex> lock(g_jvm_mutex);
    return g_javaVM;
}

JNIEnv* JniHelper::getEnv() {
    JavaVM* vm = getJavaVM();
    if (!vm) {
        LOGE("JniHelper::getEnv: JavaVM is null");
        return nullptr;
    }

    JNIEnv* env = nullptr;
    jint status = vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if (vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
            LOGE("JniHelper::getEnv: failed to attach thread");
            return nullptr;
        }
    } else if (status != JNI_OK) {
        LOGE("JniHelper::getEnv: GetEnv failed with status %d", status);
        return nullptr;
    }
    return env;
}

std::string JniHelper::jstring2string(jstring str) {
    if (!str) return "";

    JNIEnv* env = getEnv();
    if (!env) return "";

    const char* chars = env->GetStringUTFChars(str, nullptr);
    if (!chars) return "";

    std::string result(chars);
    env->ReleaseStringUTFChars(str, chars);
    return result;
}

bool JniHelper::getStaticMethodInfo(MethodInfo& info,
                                     const char* className,
                                     const char* methodName,
                                     const char* signature) {
    JNIEnv* env = getEnv();
    if (!env) return false;

    jclass classID = env->FindClass(className);
    if (!classID) {
        LOGE("JniHelper: class '%s' not found", className);
        env->ExceptionClear();
        return false;
    }

    jmethodID methodID = env->GetStaticMethodID(classID, methodName, signature);
    if (!methodID) {
        LOGE("JniHelper: static method '%s.%s%s' not found",
             className, methodName, signature);
        env->ExceptionClear();
        env->DeleteLocalRef(classID);
        return false;
    }

    info.env = env;
    info.classID = classID;
    info.methodID = methodID;
    return true;
}

bool JniHelper::getMethodInfo(MethodInfo& info,
                               const char* className,
                               const char* methodName,
                               const char* signature) {
    JNIEnv* env = getEnv();
    if (!env) return false;

    jclass classID = env->FindClass(className);
    if (!classID) {
        LOGE("JniHelper: class '%s' not found", className);
        env->ExceptionClear();
        return false;
    }

    jmethodID methodID = env->GetMethodID(classID, methodName, signature);
    if (!methodID) {
        LOGE("JniHelper: method '%s.%s%s' not found",
             className, methodName, signature);
        env->ExceptionClear();
        env->DeleteLocalRef(classID);
        return false;
    }

    info.env = env;
    info.classID = classID;
    info.methodID = methodID;
    return true;
}

} // namespace krkr

#endif // __ANDROID__
