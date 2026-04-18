package com.daidai.panel

import android.content.Intent
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.daidai.panel/app_install"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        installApk(path)
                        result.success(null)
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
