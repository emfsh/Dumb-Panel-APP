import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../storage/secure_storage.dart';
import 'app_user_agent.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

class DioClient {
  static DioClient? _instance;
  late final Dio dio;
  String _baseUrl = '';

  DioClient._() {
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...AppUserAgent.defaultHeaders,
        },
      ),
    );

    dio.interceptors.add(_SchemeRetryInterceptor(this));

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: true,
          logPrint: (obj) => _logger.d(obj),
        ),
      );
    }
  }

  static DioClient get instance {
    _instance ??= DioClient._();
    return _instance!;
  }

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    dio.options.baseUrl = _baseUrl;
    dio.options.headers.addAll(AppUserAgent.defaultHeaders);
  }

  Dio get rawDio => Dio(
    BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json', ...AppUserAgent.defaultHeaders},
    ),
  );
}

class _SchemeRetryInterceptor extends Interceptor {
  final DioClient _client;
  bool _retrying = false;

  _SchemeRetryInterceptor(this._client);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_retrying) {
      handler.next(err);
      return;
    }

    final isNetworkError = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.unknown && err.error is SocketException;

    if (!isNetworkError) {
      handler.next(err);
      return;
    }

    final currentBase = _client._baseUrl;
    final altBase = _flipScheme(currentBase);
    if (altBase == currentBase) {
      handler.next(err);
      return;
    }

    _retrying = true;
    try {
      _client.setBaseUrl(altBase);
      await SecureStorage.saveServerUrl(altBase);

      final opts = err.requestOptions;
      opts.baseUrl = altBase;
      final response = await _client.dio.fetch(opts);
      handler.resolve(response);
    } catch (retryErr) {
      _client.setBaseUrl(currentBase);
      await SecureStorage.saveServerUrl(currentBase);
      handler.next(err);
    } finally {
      _retrying = false;
    }
  }

  static String _flipScheme(String url) {
    if (url.startsWith('https://')) return 'http://${url.substring(8)}';
    if (url.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }
}
