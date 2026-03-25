import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

class SseEvent {
  final String? event;
  final String data;
  SseEvent({this.event, required this.data});
}

class SseClient {
  http.Client? _client;
  StreamSubscription? _subscription;
  bool _closed = false;

  Future<void> connect({
    required String path,
    required void Function(SseEvent event) onEvent,
    void Function()? onDone,
    void Function(dynamic error)? onError,
    bool autoReconnect = false,
  }) async {
    _closed = false;
    await _doConnect(
      path: path,
      onEvent: onEvent,
      onDone: onDone,
      onError: onError,
      autoReconnect: autoReconnect,
    );
  }

  Future<void> _doConnect({
    required String path,
    required void Function(SseEvent event) onEvent,
    void Function()? onDone,
    void Function(dynamic error)? onError,
    bool autoReconnect = false,
  }) async {
    if (_closed) return;

    final baseUrl = DioClient.instance.baseUrl;
    final token = await SecureStorage.getAccessToken();
    final url = Uri.parse('$baseUrl$path');

    _client = http.Client();
    final request = http.Request('GET', url);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await _client!.send(request);

      if (response.statusCode == 401 && !_closed) {
        // Token 可能过期，尝试刷新后重连
        onError?.call('认证失败，请重新登录');
        return;
      }

      String buffer = '';
      String? currentEvent;

      _subscription = response.stream
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              buffer += chunk;
              final lines = buffer.split('\n');
              buffer = lines.removeLast(); // 保留不完整的行

              for (final line in lines) {
                if (line.startsWith('event: ')) {
                  currentEvent = line.substring(7).trim();
                } else if (line.startsWith('data: ')) {
                  final data = line.substring(6);
                  final event = SseEvent(event: currentEvent, data: data);
                  onEvent(event);

                  // 处理 done 事件的 reconnect
                  if (currentEvent == 'done' &&
                      data == 'reconnect' &&
                      autoReconnect &&
                      !_closed) {
                    _disposeConnection();
                    Future.delayed(const Duration(seconds: 1), () {
                      _doConnect(
                        path: path,
                        onEvent: onEvent,
                        onDone: onDone,
                        onError: onError,
                        autoReconnect: autoReconnect,
                      );
                    });
                    return;
                  }

                  currentEvent = null;
                } else if (line.isEmpty) {
                  currentEvent = null;
                }
              }
            },
            onDone: () {
              if (!_closed) onDone?.call();
            },
            onError: (error) {
              if (!_closed) onError?.call(error);
            },
            cancelOnError: true,
          );
    } catch (e) {
      if (!_closed) onError?.call(e);
    }
  }

  void _disposeConnection() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  void close() {
    _closed = true;
    _disposeConnection();
  }
}
