import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../network/app_user_agent.dart';
import '../theme/app_theme.dart';

const _kGitHubRepo = 'linzixuanzz/Dumb-Panel-APP';

class AppUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.hasUpdate,
  });
}

class AppUpdateService {
  AppUpdateService._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static const _platform = MethodChannel('com.daidai.panel/app_install');

  /// Check GitHub Releases for new version.
  static Future<AppUpdateInfo?> checkUpdate() async {
    try {
      final resp = await _dio.get(
        'https://api.github.com/repos/$_kGitHubRepo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );
      final data = resp.data;
      if (data is! Map<String, dynamic>) return null;

      final tagName = (data['tag_name'] as String?)?.replaceFirst('v', '') ?? '';
      final body = data['body']?.toString() ?? '';
      final assets = data['assets'];

      String apkUrl = '';
      if (assets is List) {
        for (final asset in assets) {
          final name = asset['name']?.toString() ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url']?.toString() ?? '';
            break;
          }
        }
      }

      final currentVersion = AppUserAgent.versionLabel.split('+').first;
      final hasUpdate = tagName.isNotEmpty && _isNewer(tagName, currentVersion);

      return AppUpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        releaseNotes: body,
        downloadUrl: apkUrl,
        hasUpdate: hasUpdate,
      );
    } catch (_) {
      return null;
    }
  }

  /// Compare semantic versions: returns true if remote > local.
  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final l = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    while (r.length < 3) {
      r.add(0);
    }
    while (l.length < 3) {
      l.add(0);
    }
    for (int i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  /// Download APK and install it.
  static Future<void> downloadAndInstall(
    String url,
    ValueChanged<double> onProgress,
    VoidCallback onDone,
    ValueChanged<String> onError,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/daidai_update.apk';

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );

      onDone();

      // Trigger Android system install
      if (Platform.isAndroid) {
        await _platform.invokeMethod('installApk', {'path': filePath});
      }
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Show update dialog.
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    if (!context.mounted) return;
    final isLight = Theme.of(context).brightness == Brightness.light;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _UpdateDialog(
        info: info,
        isLight: isLight,
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final bool isLight;
  const _UpdateDialog({required this.info, required this.isLight});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  void _startDownload() {
    if (widget.info.downloadUrl.isEmpty) {
      setState(() => _error = '未找到 APK 下载链接');
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    AppUpdateService.downloadAndInstall(
      widget.info.downloadUrl,
      (p) {
        if (mounted) setState(() => _progress = p);
      },
      () {
        if (mounted) setState(() => _downloading = false);
      },
      (e) {
        if (mounted) {
          setState(() {
            _downloading = false;
            _error = '下载失败: $e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${widget.info.currentVersion}',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isLight
                      ? AppColors.slate500
                      : AppColors.slate400,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 14),
              ),
              Text(
                'v${widget.info.latestVersion}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (widget.info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '更新内容',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  widget.info.releaseNotes,
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isLight
                        ? AppColors.slate600
                        : AppColors.slate300,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress,
              color: AppColors.primary,
              backgroundColor: widget.isLight
                  ? AppColors.slate200
                  : AppColors.slate800,
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '下载中 ${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.red500),
            ),
          ],
        ],
      ),
      actions: _downloading
          ? null
          : [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('稍后'),
                      ),
                    ),
                  ),
                  if (isAndroid && widget.info.downloadUrl.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: _startDownload,
                          child: const Text('立即更新'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
    );
  }
}
