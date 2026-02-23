package org.tvp.kirikiri2

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.util.Locale

open class KR2Activity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        appContext = applicationContext
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    companion object {
        private const val TAG = "krkr2"

        @Volatile
        private var instance: KR2Activity? = null

        @Volatile
        private var appContext: Context? = null

        @JvmStatic
        fun GetInstance(): KR2Activity? {
            return instance
        }

        @JvmStatic
        fun updateMemoryInfo() {
            // No-op; memory info is fetched on demand via ActivityManager.
        }

        @JvmStatic
        fun getAvailMemory(): Long {
            val ctx = appContext ?: return 0L
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val info = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(info)
            return info.availMem
        }

        @JvmStatic
        fun getUsedMemory(): Long {
            val ctx = appContext ?: return 0L
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val info = ActivityManager.MemoryInfo()
            am?.getMemoryInfo(info)
            return info.totalMem - info.availMem
        }

        @JvmStatic
        fun getDeviceId(): String {
            val ctx = appContext ?: return ""
            return Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        }

        @JvmStatic
        fun GetVersion(): String {
            val ctx = appContext ?: return ""
            return try {
                val pm = ctx.packageManager
                val pkg = ctx.packageName
                val pi = if (Build.VERSION.SDK_INT >= 33) {
                    pm.getPackageInfo(pkg, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                }
                pi.versionName ?: ""
            } catch (e: Exception) {
                ""
            }
        }

        @JvmStatic
        fun getLocaleName(): String {
            return Locale.getDefault().language
        }

        @JvmStatic
        fun getStoragePath(): Array<String> {
            val ctx = appContext ?: return emptyArray()
            val paths = mutableListOf<String>()
            ctx.getExternalFilesDirs(null)?.forEach { file ->
                if (file != null) paths.add(file.absolutePath)
            }
            val internal = ctx.filesDir
            if (internal != null) paths.add(internal.absolutePath)
            return paths.toTypedArray()
        }

        @JvmStatic
        fun isWritableNormalOrSaf(path: String): Boolean {
            return try {
                val file = File(path)
                if (!file.exists()) {
                    file.mkdirs()
                }
                file.canWrite()
            } catch (e: Exception) {
                false
            }
        }

        @JvmStatic
        fun CreateFolders(path: String): Boolean {
            return try {
                File(path).mkdirs()
            } catch (e: Exception) {
                false
            }
        }

        @JvmStatic
        fun WriteFile(path: String, data: ByteArray): Boolean {
            return try {
                File(path).writeBytes(data)
                true
            } catch (e: Exception) {
                false
            }
        }

        @JvmStatic
        fun DeleteFile(path: String): Boolean {
            return try {
                File(path).delete()
            } catch (e: Exception) {
                false
            }
        }

        @JvmStatic
        fun RenameFile(from: String, to: String): Boolean {
            return try {
                File(from).renameTo(File(to))
            } catch (e: Exception) {
                false
            }
        }

        @JvmStatic
        fun MessageController(adType: Int, arg1: Int, arg2: Int) {
            // Ads not supported in Flutter build.
            Log.d(TAG, "MessageController ignored: $adType $arg1 $arg2")
        }

        @JvmStatic
        fun ShowMessageBox(title: String, message: String, buttons: Array<String>) {
            Log.w(TAG, "ShowMessageBox stub: $title / $message")
            // Default to first button to avoid blocking native thread.
            nativeOnMessageBoxResult(0)
        }

        @JvmStatic
        fun ShowInputBox(title: String, prompt: String, initText: String, buttons: Array<String>) {
            Log.w(TAG, "ShowInputBox stub: $title / $prompt")
            // Return the initial text and first button by default.
            nativeOnInputBoxResult(0, initText)
        }

        @JvmStatic
        fun hideTextInput() {
            // No-op; Flutter manages IME.
        }

        @JvmStatic
        fun showTextInput(x: Int, y: Int, w: Int, h: Int) {
            // No-op; Flutter manages IME.
        }

        @JvmStatic
        fun exit() {
            instance?.finish()
        }

        @JvmStatic
        private external fun nativeOnMessageBoxResult(result: Int)

        @JvmStatic
        private external fun nativeOnInputBoxResult(result: Int, text: String)
    }
}
