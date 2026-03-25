import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/notify_channel.dart';
import '../../../shared/utils/api_utils.dart';

final notificationListProvider =
    StateNotifierProvider<NotificationListNotifier, NotificationListState>((
      ref,
    ) {
      return NotificationListNotifier();
    });

class NotificationTypeOption {
  final String type;
  final String name;

  const NotificationTypeOption({required this.type, required this.name});

  factory NotificationTypeOption.fromJson(Map<String, dynamic> json) {
    return NotificationTypeOption(
      type: json['type']?.toString() ?? '',
      name: json['name']?.toString() ?? json['type']?.toString() ?? '',
    );
  }
}

const List<NotificationTypeOption> _fallbackTypes = [
  NotificationTypeOption(type: 'webhook', name: 'Webhook'),
  NotificationTypeOption(type: 'email', name: '邮件'),
  NotificationTypeOption(type: 'telegram', name: 'Telegram'),
  NotificationTypeOption(type: 'dingtalk', name: '钉钉'),
  NotificationTypeOption(type: 'wecom', name: '企业微信机器人'),
  NotificationTypeOption(type: 'wecom_app', name: '企业微信应用'),
  NotificationTypeOption(type: 'bark', name: 'Bark'),
  NotificationTypeOption(type: 'pushplus', name: 'PushPlus'),
  NotificationTypeOption(type: 'serverchan', name: 'Server酱'),
  NotificationTypeOption(type: 'feishu', name: '飞书'),
  NotificationTypeOption(type: 'gotify', name: 'Gotify'),
  NotificationTypeOption(type: 'pushdeer', name: 'PushDeer'),
  NotificationTypeOption(type: 'pushme', name: 'PushMe'),
  NotificationTypeOption(type: 'chanify', name: 'Chanify'),
  NotificationTypeOption(type: 'igot', name: 'iGot'),
  NotificationTypeOption(type: 'qmsg', name: 'Qmsg'),
  NotificationTypeOption(type: 'pushover', name: 'Pushover'),
  NotificationTypeOption(type: 'discord', name: 'Discord'),
  NotificationTypeOption(type: 'slack', name: 'Slack'),
  NotificationTypeOption(type: 'ntfy', name: 'ntfy'),
  NotificationTypeOption(type: 'wxpusher', name: 'WxPusher'),
  NotificationTypeOption(type: 'custom', name: '自定义'),
];

class NotificationListState {
  final List<NotifyChannel> items;
  final bool loading;
  final List<NotificationTypeOption> types;

  const NotificationListState({
    this.items = const [],
    this.loading = false,
    this.types = const [],
  });

  NotificationListState copyWith({
    List<NotifyChannel>? items,
    bool? loading,
    List<NotificationTypeOption>? types,
  }) {
    return NotificationListState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      types: types ?? this.types,
    );
  }
}

class NotificationListNotifier extends StateNotifier<NotificationListState> {
  NotificationListNotifier() : super(const NotificationListState());

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final dio = DioClient.instance.dio;
      final results = await Future.wait([
        dio.get(ApiEndpoints.notifications),
        dio.get(ApiEndpoints.notificationTypes),
      ]);

      final paginated = extractPaginated(results[0].data);
      final items = paginated.items
          .map((e) => NotifyChannel.fromJson(e))
          .toList();

      final typeData = extractData(results[1].data);
      final types = typeData is List
          ? typeData
                .whereType<Map>()
                .map(
                  (e) => NotificationTypeOption.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .where((option) => option.type.isNotEmpty)
                .toList()
          : <NotificationTypeOption>[];

      state = state.copyWith(
        items: items,
        loading: false,
        types: types.isNotEmpty ? types : _fallbackTypes,
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        types: state.types.isNotEmpty ? state.types : _fallbackTypes,
      );
    }
  }

  Future<void> toggle(int id, bool enabled) async {
    final dio = DioClient.instance.dio;
    if (enabled) {
      await dio.put(ApiEndpoints.notificationEnable(id));
    } else {
      await dio.put(ApiEndpoints.notificationDisable(id));
    }
    await load();
  }

  Future<void> test(int id) async {
    await DioClient.instance.dio.post(ApiEndpoints.notificationTest(id));
  }

  Future<void> delete(int id) async {
    await DioClient.instance.dio.delete(ApiEndpoints.notificationById(id));
    await load();
  }

  Future<void> create(Map<String, dynamic> data) async {
    await DioClient.instance.dio.post(ApiEndpoints.notifications, data: data);
    await load();
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    await DioClient.instance.dio.put(
      ApiEndpoints.notificationById(id),
      data: data,
    );
    await load();
  }
}

class NotificationListPage extends ConsumerStatefulWidget {
  const NotificationListPage({super.key});

  @override
  ConsumerState<NotificationListPage> createState() =>
      _NotificationListPageState();
}

class _NotificationListPageState extends ConsumerState<NotificationListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(notificationListProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationListProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '通知渠道',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showChannelDialog(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withAlpha(80),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () =>
                    ref.read(notificationListProvider.notifier).load(),
                child: state.loading && state.items.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : state.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_off,
                              size: 56,
                              color: AppColors.slate400.withAlpha(120),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '暂无通知渠道',
                              style: TextStyle(color: AppColors.slate400),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: state.items.length,
                        itemBuilder: (_, i) {
                          final channel = state.items[i];
                          return _ChannelCard(
                            channel: channel,
                            typeLabel: _typeName(state.types, channel.type),
                            isLight: isLight,
                            onEdit: () => _showChannelDialog(channel: channel),
                            onToggle: () => ref
                                .read(notificationListProvider.notifier)
                                .toggle(channel.id, !channel.enabled),
                            onTest: () => _doTest(channel),
                            onDelete: () => _confirmDelete(channel),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doTest(NotifyChannel channel) async {
    try {
      await ref.read(notificationListProvider.notifier).test(channel.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('测试通知已发送')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractMessage(error, '测试发送失败'))));
    }
  }

  Future<void> _confirmDelete(NotifyChannel channel) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除通知渠道'),
        content: Text('确定要删除「${channel.name}」吗？'),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red500,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(notificationListProvider.notifier).delete(channel.id);
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_extractMessage(error, '删除失败'))));
      }
    }
  }

  void _showChannelDialog({NotifyChannel? channel}) {
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController(text: channel?.name ?? '');
    final configController = TextEditingController(
      text: const JsonEncoder.withIndent(
        '  ',
      ).convert(channel?.config ?? <String, dynamic>{}),
    );

    final availableTypes = ref.read(notificationListProvider).types.isNotEmpty
        ? ref.read(notificationListProvider).types
        : _fallbackTypes;
    String selectedType = channel?.type ?? availableTypes.first.type;
    if (!availableTypes.any((item) => item.type == selectedType)) {
      selectedType = availableTypes.first.type;
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        final navigator = Navigator.of(dialogContext);
        return StatefulBuilder(
          builder: (dialogBodyContext, setDialogState) {
            return AlertDialog(
              title: Text(channel == null ? '新建通知渠道' : '编辑通知渠道'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: '名称'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: availableTypes
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.type,
                                child: Text(item.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: configController,
                        minLines: 8,
                        maxLines: 14,
                        decoration: const InputDecoration(
                          labelText: '配置 JSON',
                          alignLabelWithHint: true,
                          hintText:
                              '{\n  "url": "https://example.com/webhook"\n}',
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '已有渠道会自动回填配置。支持直接编辑 JSON，保存时会按后端需要的格式提交。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            dialogBodyContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => navigator.pop(),
                          child: const Text('取消'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: FilledButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('名称不能为空')),
                              );
                              return;
                            }

                            final configMap = _parseConfig(
                              configController.text,
                            );
                            if (configMap == null) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('配置 JSON 格式错误')),
                              );
                              return;
                            }

                            final payload = {
                              'name': name,
                              'type': selectedType,
                              'config': jsonEncode(configMap),
                            };

                            try {
                              if (channel == null) {
                                await ref
                                    .read(notificationListProvider.notifier)
                                    .create(payload);
                              } else {
                                await ref
                                    .read(notificationListProvider.notifier)
                                    .update(channel.id, payload);
                              }

                              if (!mounted) {
                                return;
                              }

                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    channel == null ? '创建成功' : '保存成功',
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (!mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _extractMessage(
                                      error,
                                      channel == null ? '创建失败' : '保存失败',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(channel == null ? '创建' : '保存'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final NotifyChannel channel;
  final String typeLabel;
  final bool isLight;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _ChannelCard({
    required this.channel,
    required this.typeLabel,
    required this.isLight,
    required this.onEdit,
    required this.onToggle,
    required this.onTest,
    required this.onDelete,
  });

  IconData _typeIcon() {
    switch (channel.type) {
      case 'email':
        return Icons.email_outlined;
      case 'telegram':
        return Icons.send;
      case 'dingtalk':
        return Icons.chat;
      case 'wecom':
      case 'wecom_app':
        return Icons.business;
      case 'bark':
        return Icons.phone_iphone;
      default:
        return Icons.webhook;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColors.slate900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? AppColors.slate200 : AppColors.slate800,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: channel.enabled
                  ? AppColors.primary.withAlpha(25)
                  : AppColors.slate200.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _typeIcon(),
              size: 18,
              color: channel.enabled ? AppColors.primary : AppColors.slate400,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: isLight ? AppColors.slate500 : AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTest,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.send, size: 16, color: AppColors.blue500),
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.blue500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                channel.enabled ? Icons.toggle_on : Icons.toggle_off,
                size: 28,
                color: channel.enabled ? AppColors.primary : AppColors.slate400,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.red500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _typeName(List<NotificationTypeOption> types, String type) {
  for (final item in types) {
    if (item.type == type) {
      return item.name;
    }
  }
  return type;
}

Map<String, dynamic>? _parseConfig(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {}

  return null;
}

String _extractMessage(dynamic error, String fallback) {
  try {
    final data = (error as dynamic).response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
  } catch (_) {}
  return fallback;
}
