import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/auth/auth_interceptor.dart';
import 'core/auth/auth_provider.dart';
import 'core/network/app_user_agent.dart';
import 'core/network/dio_client.dart';
import 'core/storage/secure_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppUserAgent.initialize();

  // 恢复服务器地址
  final serverUrl = await SecureStorage.getServerUrl();
  if (serverUrl != null && serverUrl.isNotEmpty) {
    DioClient.instance.setBaseUrl(serverUrl);
  }

  final container = ProviderContainer();

  // 注入认证拦截器
  DioClient.instance.dio.interceptors.insert(
    0,
    AuthInterceptor(
      onAuthFailed: () {
        container.read(authProvider.notifier).setUnauthenticated();
      },
    ),
  );

  // 恢复登录状态时必须向服务端校验，避免本地残留 token 误判为已登录。
  if (serverUrl != null && serverUrl.isNotEmpty) {
    await container.read(authProvider.notifier).checkAuthStatus();
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const DaidaiApp()),
  );
}
