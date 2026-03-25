import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/user.dart';
import '../storage/secure_storage.dart';
import 'auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final User? user;
  final bool needsInit;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.needsInit = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    bool? needsInit,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      needsInit: needsInit ?? this.needsInit,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState());

  Future<void> restoreSession() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    final cachedUser = await SecureStorage.getUser();
    state = AuthState(
      status: AuthStatus.authenticated,
      user: cachedUser,
      needsInit: state.needsInit,
    );
  }

  Future<void> checkAuthStatus({bool verifyRemote = true}) async {
    await restoreSession();
    if (!verifyRemote || state.status != AuthStatus.authenticated) {
      return;
    }

    try {
      final user = await _authService.getUser();
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // 启动探活失败时保留本地登录态，等真正的业务请求再决定是否失效。
    }
  }

  Future<void> checkInit() async {
    try {
      final needsInit = await _authService.needsInitialization();
      state = state.copyWith(needsInit: needsInit);
    } catch (e) {
      // 出错时默认不需要初始化，直接显示登录
      state = state.copyWith(needsInit: false);
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? totpCode,
  }) async {
    state = state.copyWith(error: null);
    try {
      final result = await _authService.login(
        username: username,
        password: password,
        totpCode: totpCode,
      );

      if (result.containsKey('access_token')) {
        // 直接用登录响应中的 user 数据，避免额外请求
        if (result.containsKey('user') && result['user'] != null) {
          final user = User.fromJson(result['user'] as Map<String, dynamic>);
          await SecureStorage.saveUser(user);
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
        } else {
          final user = await _authService.getUser();
          state = state.copyWith(status: AuthStatus.authenticated, user: user);
        }
      }
      return result;
    } catch (e) {
      final msg = _extractErrorMessage(e);
      state = state.copyWith(error: msg);
      rethrow;
    }
  }

  Future<void> initAdmin(String username, String password) async {
    await _authService.initAdmin(username, password);
    state = state.copyWith(needsInit: false);
  }

  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> refreshUser() async {
    try {
      final user = await _authService.getUser();
      state = state.copyWith(user: user);
    } catch (_) {}
  }

  void setUnauthenticated() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _extractErrorMessage(dynamic e) {
    if (e is Exception) {
      try {
        final dioError = e as dynamic;
        if (dioError.response?.data != null) {
          return dioError.response.data['message']?.toString() ?? '操作失败';
        }
      } catch (_) {}
    }
    return '网络错误，请检查连接';
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});
