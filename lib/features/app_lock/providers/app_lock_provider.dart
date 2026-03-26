import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/storage/secure_storage.dart';

class AppLockConfig {
  final bool enabled;
  final String passwordHash;
  final String patternHash;
  final bool biometricEnabled;

  const AppLockConfig({
    this.enabled = false,
    this.passwordHash = '',
    this.patternHash = '',
    this.biometricEnabled = false,
  });

  bool get hasPassword => passwordHash.isNotEmpty;
  bool get hasPattern => patternHash.isNotEmpty;
  bool get hasAnyMethod => hasPassword || hasPattern || biometricEnabled;

  AppLockConfig copyWith({
    bool? enabled,
    String? passwordHash,
    String? patternHash,
    bool? biometricEnabled,
  }) {
    return AppLockConfig(
      enabled: enabled ?? this.enabled,
      passwordHash: passwordHash ?? this.passwordHash,
      patternHash: patternHash ?? this.patternHash,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'password_hash': passwordHash,
    'pattern_hash': patternHash,
    'biometric_enabled': biometricEnabled,
  };

  factory AppLockConfig.fromJson(Map<String, dynamic> json) {
    return AppLockConfig(
      enabled: json['enabled'] == true,
      passwordHash: json['password_hash']?.toString() ?? '',
      patternHash: json['pattern_hash']?.toString() ?? '',
      biometricEnabled: json['biometric_enabled'] == true,
    );
  }
}

class AppLockState {
  final bool loading;
  final bool locked;
  final AppLockConfig config;
  final List<BiometricType> availableBiometrics;

  const AppLockState({
    this.loading = false,
    this.locked = false,
    this.config = const AppLockConfig(),
    this.availableBiometrics = const [],
  });

  bool get biometricAvailable => availableBiometrics.isNotEmpty;
  bool get isEnabled => config.enabled && config.hasAnyMethod;
  bool get hasPassword => config.hasPassword;
  bool get hasPattern => config.hasPattern;
  bool get hasBiometric => config.biometricEnabled && biometricAvailable;

  String get biometricLabel {
    final hasFace = availableBiometrics.contains(BiometricType.face);
    final hasFingerprint = availableBiometrics.contains(
      BiometricType.fingerprint,
    );
    if (hasFace && hasFingerprint) return '指纹 / 人脸';
    if (hasFace) return '人脸';
    if (hasFingerprint) return '指纹';
    return '生物识别';
  }

  AppLockState copyWith({
    bool? loading,
    bool? locked,
    AppLockConfig? config,
    List<BiometricType>? availableBiometrics,
  }) {
    return AppLockState(
      loading: loading ?? this.loading,
      locked: locked ?? this.locked,
      config: config ?? this.config,
      availableBiometrics: availableBiometrics ?? this.availableBiometrics,
    );
  }
}

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController() : super(const AppLockState());

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<void> initialize() async {
    state = state.copyWith(loading: true);
    final rawConfig = await SecureStorage.getAppLockConfig();
    final biometrics = await _readAvailableBiometrics();
    final nextConfig = _sanitizeConfig(
      AppLockConfig.fromJson(rawConfig ?? const <String, dynamic>{}),
      biometrics,
    );
    state = state.copyWith(
      loading: false,
      config: nextConfig,
      availableBiometrics: biometrics,
    );
    await SecureStorage.saveAppLockConfig(nextConfig.toJson());
  }

  Future<void> setEnabled(bool enabled) async {
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(enabled: enabled),
      state.availableBiometrics,
    );
    if (enabled && !nextConfig.hasAnyMethod) {
      throw StateError('请先至少配置一种验证方式');
    }
    await _saveConfig(nextConfig);
    if (!nextConfig.enabled) {
      state = state.copyWith(locked: false);
    }
  }

  Future<void> savePassword(String value) async {
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(enabled: true, passwordHash: _hashSecret(value)),
      state.availableBiometrics,
    );
    await _saveConfig(nextConfig);
  }

  Future<void> removePassword() async {
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(passwordHash: ''),
      state.availableBiometrics,
    );
    await _saveConfig(nextConfig);
  }

  Future<void> savePattern(List<int> pattern) async {
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(
        enabled: true,
        patternHash: _hashSecret(pattern.join('-')),
      ),
      state.availableBiometrics,
    );
    await _saveConfig(nextConfig);
  }

  Future<void> removePattern() async {
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(patternHash: ''),
      state.availableBiometrics,
    );
    await _saveConfig(nextConfig);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled && state.availableBiometrics.isEmpty) {
      throw StateError('当前设备未检测到可用的指纹或人脸');
    }
    final nextConfig = _sanitizeConfig(
      state.config.copyWith(enabled: true, biometricEnabled: enabled),
      state.availableBiometrics,
    );
    await _saveConfig(nextConfig);
  }

  void lockIfEnabled() {
    if (state.isEnabled) {
      state = state.copyWith(locked: true);
    }
  }

  void unlockSession() {
    state = state.copyWith(locked: false);
  }

  void resetSession() {
    state = state.copyWith(locked: false);
  }

  Future<bool> unlockWithPassword(String value) async {
    if (!state.hasPassword) {
      return false;
    }
    final ok = _hashSecret(value) == state.config.passwordHash;
    if (ok) {
      unlockSession();
    }
    return ok;
  }

  Future<bool> unlockWithPattern(List<int> pattern) async {
    if (!state.hasPattern) {
      return false;
    }
    final ok = _hashSecret(pattern.join('-')) == state.config.patternHash;
    if (ok) {
      unlockSession();
    }
    return ok;
  }

  Future<bool> unlockWithBiometric() async {
    if (!state.hasBiometric) {
      return false;
    }

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: '验证身份以进入呆呆面板',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
      if (ok) {
        unlockSession();
      }
      return ok;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _saveConfig(AppLockConfig config) async {
    await SecureStorage.saveAppLockConfig(config.toJson());
    state = state.copyWith(config: config);
  }

  Future<List<BiometricType>> _readAvailableBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        return const [];
      }
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return const [];
    }
  }

  AppLockConfig _sanitizeConfig(
    AppLockConfig config,
    List<BiometricType> availableBiometrics,
  ) {
    final biometricEnabled =
        config.biometricEnabled && availableBiometrics.isNotEmpty;
    final hasAnyMethod =
        config.passwordHash.isNotEmpty ||
        config.patternHash.isNotEmpty ||
        biometricEnabled;
    return config.copyWith(
      enabled: config.enabled && hasAnyMethod,
      biometricEnabled: biometricEnabled,
    );
  }

  String _hashSecret(String value) {
    final bytes = utf8.encode('daidai_app_lock::$value');
    return sha256.convert(bytes).toString();
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>((
  ref,
) {
  return AppLockController();
});
