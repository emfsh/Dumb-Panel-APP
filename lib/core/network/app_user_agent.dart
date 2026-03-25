import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUserAgent {
  AppUserAgent._();

  static String _userAgent = _fallbackUserAgent;
  static String _platform = _detectPlatform();
  static String _version = 'unknown';
  static String _buildNumber = '';

  static String get value => _userAgent;

  static Map<String, String> get defaultHeaders => {
    'User-Agent': _userAgent,
    'X-Client-App': 'daidai-panel-app',
    'X-Client-Type': 'app',
    'X-Client-Platform': _platform,
    'X-Client-Version': versionLabel,
  };

  static String get versionLabel =>
      _buildNumber.isEmpty ? _version : '$_version+$_buildNumber';

  static Future<void> initialize() async {
    _platform = _detectPlatform();

    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version.trim().isEmpty ? 'unknown' : info.version.trim();
      _buildNumber = info.buildNumber.trim();
    } catch (_) {
      _version = 'unknown';
      _buildNumber = '';
    }

    _userAgent = _buildUserAgent();
  }

  static String _buildUserAgent() {
    switch (_platform) {
      case 'android':
        return 'DaidaiPanelApp/$versionLabel (Android; Flutter)';
      case 'ios':
        return 'DaidaiPanelApp/$versionLabel (iPhone; iOS; Flutter)';
      case 'macos':
        return 'DaidaiPanelApp/$versionLabel (macOS; Flutter)';
      case 'windows':
        return 'DaidaiPanelApp/$versionLabel (Windows; Flutter)';
      case 'linux':
        return 'DaidaiPanelApp/$versionLabel (Linux; Flutter)';
      case 'web':
        return 'DaidaiPanelApp/$versionLabel (Web; Flutter)';
      default:
        return _fallbackUserAgent;
    }
  }

  static String _detectPlatform() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static const String _fallbackUserAgent = 'DaidaiPanelApp/unknown (Flutter)';
}
