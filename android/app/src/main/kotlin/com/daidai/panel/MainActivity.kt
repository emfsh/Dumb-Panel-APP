package com.daidai.panel

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.daidai.panel/app_install"
    private val trustedDownloadHosts = setOf(
        "github.com",
        "objects.githubusercontent.com",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    val sourceHost = call.argument<String>("sourceHost")
                    if (path != null) {
                        try {
                            installApk(path, sourceHost)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_BLOCKED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun installApk(filePath: String, sourceHost: String?) {
        val normalizedHost = sourceHost?.lowercase()
        if (normalizedHost.isNullOrBlank() || !isTrustedHost(normalizedHost)) {
            throw IllegalArgumentException("Untrusted update source")
        }

        val file = File(filePath)
        if (!file.exists() || !file.isFile) {
            throw IllegalArgumentException("APK file does not exist")
        }
        if (!isFileInsideCache(file)) {
            throw IllegalArgumentException("APK file path is not allowed")
        }
        if (!verifyArchivePackage(file)) {
            throw IllegalArgumentException("APK verification failed")
        }

        val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun isTrustedHost(host: String): Boolean {
        return host in trustedDownloadHosts || host.endsWith(".githubusercontent.com")
    }

    private fun isFileInsideCache(file: File): Boolean {
        val cacheRoot = cacheDir.canonicalFile
        val targetFile = file.canonicalFile
        return targetFile.path.startsWith("${cacheRoot.path}${File.separator}")
    }

    private fun verifyArchivePackage(file: File): Boolean {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        } ?: return false

        if (packageInfo.packageName != packageName) {
            return false
        }

        return signaturesMatch(packageInfo)
    }

    private fun signaturesMatch(archiveInfo: android.content.pm.PackageInfo): Boolean {
        val installedInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        }

        return signingDigests(installedInfo).intersect(signingDigests(archiveInfo)).isNotEmpty()
    }

    private fun signingDigests(packageInfo: android.content.pm.PackageInfo): Set<Int> {
        val signingInfo = packageInfo.signingInfo ?: return emptySet()
        val signatures = if (signingInfo.hasMultipleSigners()) {
            signingInfo.apkContentsSigners
        } else {
            signingInfo.signingCertificateHistory
        }
        return signatures.map { it.toByteArray().contentHashCode() }.toSet()
    }
}
