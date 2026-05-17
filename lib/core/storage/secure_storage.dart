import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/user.dart';

const Object _panelFieldUnset = Object();

/// 面板配置信息
class PanelConfig {
  final String url;
  final String name;
  final String? username;
  final String? password;
  final bool rememberPassword;
  final bool autoLogin;

  const PanelConfig({
    required this.url,
    this.name = '',
    this.username,
    this.password,
    this.rememberPassword = false,
    this.autoLogin = false,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name.isEmpty ? url : name,
    'username': username,
    'password': password,
    'rememberPassword': rememberPassword,
    'autoLogin': autoLogin,
  };

  factory PanelConfig.fromJson(Map<String, dynamic> json) => PanelConfig(
    url: json['url'] as String,
    name: json['name'] as String? ?? '',
    username: json['username'] as String?,
    password: json['password'] as String?,
    rememberPassword: json['rememberPassword'] as bool? ?? false,
    autoLogin: json['autoLogin'] as bool? ?? false,
  );

  PanelConfig copyWith({
    String? url,
    String? name,
    Object? username = _panelFieldUnset,
    Object? password = _panelFieldUnset,
    bool? rememberPassword,
    bool? autoLogin,
  }) {
    return PanelConfig(
      url: url ?? this.url,
      name: name ?? this.name,
      username: identical(username, _panelFieldUnset)
          ? this.username
          : username as String?,
      password: identical(password, _panelFieldUnset)
          ? this.password
          : password as String?,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      autoLogin: autoLogin ?? this.autoLogin,
    );
  }

  PanelConfig sanitizedForStorage() => this;
}

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _serverUrlKey = 'server_url';
  static const _serverListKey = 'server_list';
  static const _panelsKey = 'panels_config';
  static const _userKey = 'auth_user';
  static const _appLockConfigKey = 'app_lock_config';

  // Token
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: _accessTokenKey);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  static Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  static Future<void> saveUser(User user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  static Future<User?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        return User.fromJson(data);
      }
      if (data is Map) {
        return User.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}

    return null;
  }

  static Future<void> clearUser() => _storage.delete(key: _userKey);

  static Future<void> clearAuthSession() async {
    await clearTokens();
    await clearUser();
  }

  static Future<void> saveAppLockConfig(Map<String, dynamic> config) =>
      _storage.write(key: _appLockConfigKey, value: jsonEncode(config));

  static Future<Map<String, dynamic>?> getAppLockConfig() async {
    final raw = await _storage.read(key: _appLockConfigKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearAppLockConfig() =>
      _storage.delete(key: _appLockConfigKey);

  // Server URL
  static Future<void> saveServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  static Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey);
  }

  // Server List (legacy)
  static Future<void> saveServerList(List<String> servers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_serverListKey, servers);
  }

  static Future<List<String>> getServerList() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_serverListKey) ?? [];
  }

  // Panels
  static Future<void> savePanels(List<PanelConfig> panels) async {
    final sanitized = panels.map((p) => p.sanitizedForStorage()).toList();
    final json = sanitized.map((p) => jsonEncode(p.toJson())).toList();
    await _storage.write(key: _panelsKey, value: jsonEncode(json));
  }

  static Future<List<PanelConfig>> getPanels() async {
    final raw = await _storage.read(key: _panelsKey);
    if (raw == null) {
      // 迁移旧数据
      final oldList = await getServerList();
      if (oldList.isNotEmpty) {
        final panels = oldList
            .map((url) => PanelConfig(url: url, name: url))
            .toList();
        await savePanels(panels);
        return panels;
      }
      return [];
    }
    try {
      final list = jsonDecode(raw) as List;
      final panels = list
          .map((e) => PanelConfig.fromJson(jsonDecode(e as String)))
          .map((panel) => panel.sanitizedForStorage())
          .toList();
      await savePanels(panels);
      return panels;
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePanel(PanelConfig panel) async {
    final panels = await getPanels();
    final sanitized = panel.sanitizedForStorage();
    final idx = panels.indexWhere((p) => p.url == sanitized.url);
    if (idx >= 0) {
      panels[idx] = sanitized;
    } else {
      panels.insert(0, sanitized);
    }
    await savePanels(panels);
  }

  static Future<void> removePanel(String url) async {
    final panels = await getPanels();
    panels.removeWhere((p) => p.url == url);
    await savePanels(panels);
  }

  static Future<void> writeValue(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<String?> readValue(String key) => _storage.read(key: key);
}
