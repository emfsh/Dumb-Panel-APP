import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/task.dart';
import '../../../shared/utils/api_utils.dart';
import '../providers/task_provider.dart';

class TaskFormPrefill {
  final String name;
  final String command;
  final String? taskType;
  final String? cronExpression;

  const TaskFormPrefill({
    required this.name,
    required this.command,
    this.taskType,
    this.cronExpression,
  });
}

class TaskFormPage extends ConsumerStatefulWidget {
  final Task? task;
  final TaskFormPrefill? prefill;

  const TaskFormPage({super.key, this.task, this.prefill});

  @override
  ConsumerState<TaskFormPage> createState() => _TaskFormPageState();
}

enum _RandomDelayMode { inherit, disabled, custom }

class _TaskNotificationChannel {
  final int id;
  final String name;
  final String type;
  final bool enabled;

  const _TaskNotificationChannel({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
  });

  factory _TaskNotificationChannel.fromJson(Map<String, dynamic> json) {
    return _TaskNotificationChannel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      enabled: json['enabled'] == true,
    );
  }
}

class _TaskFormPageState extends ConsumerState<TaskFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _commandController;
  late final TextEditingController _cronController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _randomDelayController;
  late final TextEditingController _retriesController;
  late final TextEditingController _retryIntervalController;
  late final TextEditingController _dependsOnController;
  late final TextEditingController _taskBeforeController;
  late final TextEditingController _taskAfterController;
  late final TextEditingController _labelController;

  bool _saving = false;
  bool _loadingChannels = false;
  String _taskType = 'cron';
  bool _notifyOnFailure = true;
  bool _notifyOnSuccess = false;
  bool _allowMultipleInstances = false;
  int? _notificationChannelId;
  _RandomDelayMode _randomDelayMode = _RandomDelayMode.inherit;
  final List<String> _labels = [];
  List<_TaskNotificationChannel> _notificationChannels = const [];

  bool get isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final prefill = widget.prefill;
    _nameController = TextEditingController(
      text: task?.name ?? prefill?.name ?? '',
    );
    _commandController = TextEditingController(
      text: task?.command ?? prefill?.command ?? '',
    );
    _cronController = TextEditingController(
      text: task?.cronExpression.isNotEmpty == true
          ? task!.cronExpression
          : (prefill?.cronExpression ?? '0 0 * * *'),
    );
    _timeoutController = TextEditingController(
      text: '${task?.timeout ?? 86400}',
    );
    _randomDelayController = TextEditingController(
      text: '${task?.randomDelaySeconds ?? 60}',
    );
    _retriesController = TextEditingController(
      text: '${task?.maxRetries ?? 0}',
    );
    _retryIntervalController = TextEditingController(
      text: '${task?.retryInterval ?? 60}',
    );
    _dependsOnController = TextEditingController(
      text: task?.dependsOn?.toString() ?? '',
    );
    _taskBeforeController = TextEditingController(text: task?.taskBefore ?? '');
    _taskAfterController = TextEditingController(text: task?.taskAfter ?? '');
    _labelController = TextEditingController();

    _taskType = task?.taskType ?? prefill?.taskType ?? 'cron';
    _notifyOnFailure = task?.notifyOnFailure ?? true;
    _notifyOnSuccess = task?.notifyOnSuccess ?? false;
    _allowMultipleInstances = task?.allowMultipleInstances ?? false;
    _notificationChannelId = task?.notificationChannelId;
    _labels
      ..clear()
      ..addAll(task?.labelList ?? const []);
    _randomDelayMode = _resolveRandomDelayMode(task?.randomDelaySeconds);

    Future.microtask(_loadNotificationChannels);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _cronController.dispose();
    _timeoutController.dispose();
    _randomDelayController.dispose();
    _retriesController.dispose();
    _retryIntervalController.dispose();
    _dependsOnController.dispose();
    _taskBeforeController.dispose();
    _taskAfterController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  _RandomDelayMode _resolveRandomDelayMode(int? randomDelaySeconds) {
    if (randomDelaySeconds == null) {
      return _RandomDelayMode.inherit;
    }
    if (randomDelaySeconds <= 0) {
      return _RandomDelayMode.disabled;
    }
    return _RandomDelayMode.custom;
  }

  Future<void> _loadNotificationChannels() async {
    setState(() => _loadingChannels = true);
    try {
      final response = await DioClient.instance.dio.get(
        ApiEndpoints.notificationChannels,
      );
      final data = extractData(response.data);
      final channels = data is List
          ? data
                .whereType<Map>()
                .map(
                  (item) => _TaskNotificationChannel.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : <_TaskNotificationChannel>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationChannels = channels;
        _loadingChannels = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingChannels = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addLabel() {
    final label = _labelController.text.trim();
    if (label.isEmpty || _labels.contains(label)) {
      _labelController.clear();
      return;
    }
    setState(() {
      _labels.add(label);
      _labelController.clear();
    });
  }

  int _parseInt(TextEditingController controller, int fallback) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  int? _parseOptionalPositiveInt(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_labelController.text.trim().isNotEmpty) {
      _addLabel();
    }

    final randomDelaySeconds = switch (_randomDelayMode) {
      _RandomDelayMode.inherit => null,
      _RandomDelayMode.disabled => 0,
      _RandomDelayMode.custom => int.tryParse(
        _randomDelayController.text.trim(),
      ),
    };

    if (_randomDelayMode == _RandomDelayMode.custom &&
        (randomDelaySeconds == null || randomDelaySeconds <= 0)) {
      _showMessage('请输入大于 0 的随机延迟秒数');
      return;
    }

    final data = <String, dynamic>{
      'name': _nameController.text.trim(),
      'command': _commandController.text.trim(),
      'cron_expression': _taskType == 'cron' ? _cronController.text.trim() : '',
      'task_type': _taskType,
      'timeout': _parseInt(_timeoutController, 86400),
      'random_delay_seconds': randomDelaySeconds,
      'max_retries': _parseInt(_retriesController, 0),
      'retry_interval': _parseInt(_retryIntervalController, 60),
      'notify_on_failure': _notifyOnFailure,
      'notify_on_success': _notifyOnSuccess,
      'notification_channel_id': _notificationChannelId,
      'labels': _labels,
      'depends_on': _parseOptionalPositiveInt(_dependsOnController),
      'task_before': _taskBeforeController.text.trim(),
      'task_after': _taskAfterController.text.trim(),
      'allow_multiple_instances': _allowMultipleInstances,
    };

    setState(() => _saving = true);

    try {
      if (isEditing) {
        await DioClient.instance.dio.put(
          ApiEndpoints.taskById(widget.task!.id),
          data: data,
        );
      } else {
        await DioClient.instance.dio.post(ApiEndpoints.tasks, data: data);
      }
      await ref.read(taskProvider.notifier).load(refresh: true);
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      _showMessage(_extractTaskSaveError(error, '保存失败'));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  List<_TaskNotificationChannel> get _channelOptions {
    final channels = [..._notificationChannels];
    final selectedId = _notificationChannelId;
    if (selectedId != null &&
        channels.every((channel) => channel.id != selectedId)) {
      channels.insert(
        0,
        _TaskNotificationChannel(
          id: selectedId,
          name: widget.task?.notificationChannelName ?? '当前绑定渠道 #$selectedId',
          type: 'unknown',
          enabled: widget.task?.notificationChannelEnabled ?? false,
        ),
      );
    }
    return channels;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑任务' : '新建任务'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size(84, 38),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(title: '基本信息', subtitle: '先把任务的执行方式和基础命令配置完整。'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '任务名称',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入任务名称' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _commandController,
                decoration: const InputDecoration(
                  labelText: '执行命令',
                  prefixIcon: Icon(Icons.code),
                  hintText: '例如：task demo.py 或 python3 demo.py',
                ),
                minLines: 3,
                maxLines: 5,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入执行命令' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _taskType,
                decoration: const InputDecoration(
                  labelText: '任务类型',
                  prefixIcon: Icon(Icons.tune_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cron', child: Text('常规定时')),
                  DropdownMenuItem(value: 'manual', child: Text('手动运行')),
                  DropdownMenuItem(value: 'startup', child: Text('开机运行')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _taskType = value);
                },
              ),
              const SizedBox(height: 14),
              if (_taskType == 'cron') ...[
                TextFormField(
                  controller: _cronController,
                  decoration: const InputDecoration(
                    labelText: 'Cron 表达式',
                    prefixIcon: Icon(Icons.schedule),
                    hintText: '0 0 * * *',
                  ),
                  validator: (value) {
                    if (_taskType != 'cron') {
                      return null;
                    }
                    return value == null || value.trim().isEmpty
                        ? '请输入 Cron 表达式'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CronPreset(
                      label: '每小时',
                      value: '0 0 * * * *',
                      onTap: (value) => _cronController.text = value,
                    ),
                    _CronPreset(
                      label: '每天 9 点',
                      value: '0 0 9 * * *',
                      onTap: (value) => _cronController.text = value,
                    ),
                    _CronPreset(
                      label: '每天 0 点',
                      value: '0 0 0 * * *',
                      onTap: (value) => _cronController.text = value,
                    ),
                  ],
                ),
              ] else ...[
                _InfoCard(
                  icon: Icons.info_outline,
                  message: _taskType == 'manual'
                      ? '手动运行任务不会自动调度，只会在你点击运行时执行。'
                      : '开机运行任务会在面板服务启动后自动执行一次，也可以手动触发。',
                ),
              ],
              const SizedBox(height: 14),
              _LabelEditor(
                labels: _labels,
                controller: _labelController,
                onAdd: _addLabel,
                onRemove: (label) => setState(() => _labels.remove(label)),
              ),
              const SizedBox(height: 28),
              _SectionTitle(title: '执行策略', subtitle: '这些配置会直接影响任务的重试、延迟和依赖行为。'),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 560;
                  final fieldWidth = wide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _timeoutController,
                          decoration: const InputDecoration(
                            labelText: '超时(秒)',
                            prefixIcon: Icon(Icons.timer_outlined),
                            hintText: '0 表示不限',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _retriesController,
                          decoration: const InputDecoration(
                            labelText: '最大重试次数',
                            prefixIcon: Icon(Icons.refresh),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _retryIntervalController,
                          decoration: const InputDecoration(
                            labelText: '重试间隔(秒)',
                            prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _dependsOnController,
                          decoration: const InputDecoration(
                            labelText: '依赖任务 ID',
                            prefixIcon: Icon(Icons.link_outlined),
                            hintText: '可选',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                '随机延迟',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SelectionChip(
                    label: '继承系统设置',
                    selected: _randomDelayMode == _RandomDelayMode.inherit,
                    onTap: () => setState(
                      () => _randomDelayMode = _RandomDelayMode.inherit,
                    ),
                  ),
                  _SelectionChip(
                    label: '不随机延迟',
                    selected: _randomDelayMode == _RandomDelayMode.disabled,
                    onTap: () => setState(
                      () => _randomDelayMode = _RandomDelayMode.disabled,
                    ),
                  ),
                  _SelectionChip(
                    label: '任务单独设置',
                    selected: _randomDelayMode == _RandomDelayMode.custom,
                    onTap: () => setState(
                      () => _randomDelayMode = _RandomDelayMode.custom,
                    ),
                  ),
                ],
              ),
              if (_randomDelayMode == _RandomDelayMode.custom) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _randomDelayController,
                  decoration: const InputDecoration(
                    labelText: '随机延迟秒数',
                    prefixIcon: Icon(Icons.shuffle_outlined),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '未单独设置时继续沿用系统设置里的全局随机延迟。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: '通知与并发',
                subtitle: '把任务通知和实例行为补齐，避免和面板配置不一致。',
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _notifyOnFailure,
                contentPadding: EdgeInsets.zero,
                title: const Text('失败时通知'),
                subtitle: const Text('任务执行失败后发送通知'),
                onChanged: (value) => setState(() => _notifyOnFailure = value),
              ),
              SwitchListTile.adaptive(
                value: _notifyOnSuccess,
                contentPadding: EdgeInsets.zero,
                title: const Text('成功时通知'),
                subtitle: const Text('任务执行成功后也发送通知'),
                onChanged: (value) => setState(() => _notifyOnSuccess = value),
              ),
              SwitchListTile.adaptive(
                value: _allowMultipleInstances,
                contentPadding: EdgeInsets.zero,
                title: const Text('允许多实例'),
                subtitle: const Text('运行中时仍允许再次触发新实例'),
                onChanged: (value) =>
                    setState(() => _allowMultipleInstances = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _notificationChannelId,
                decoration: InputDecoration(
                  labelText: '通知渠道',
                  prefixIcon: _loadingChannels
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('全部启用渠道'),
                  ),
                  ..._channelOptions.map(
                    (channel) => DropdownMenuItem<int?>(
                      value: channel.id,
                      child: Text(
                        channel.enabled
                            ? '${channel.name} (${channel.type})'
                            : '${channel.name} (${channel.type}，已禁用)',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _notificationChannelId = value),
              ),
              const SizedBox(height: 6),
              Text(
                '留空时，任务通知仍按全部启用的渠道发送。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              _SectionTitle(title: '钩子脚本', subtitle: '和面板保持一致，支持前置脚本与后置脚本。'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taskBeforeController,
                decoration: const InputDecoration(
                  labelText: '前置脚本',
                  prefixIcon: Icon(Icons.playlist_play_outlined),
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 6,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _taskAfterController,
                decoration: const InputDecoration(
                  labelText: '后置脚本',
                  prefixIcon: Icon(Icons.wrap_text_outlined),
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _InfoCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(height: 1.5, color: AppColors.slate700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelEditor extends StatelessWidget {
  final List<String> labels;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _LabelEditor({
    required this.labels,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '标签',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...labels.map(
              (label) => InputChip(
                label: Text(label),
                onDeleted: () => onRemove(label),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '添加标签',
                  isDense: true,
                  suffixIcon: IconButton(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ),
                onSubmitted: (_) => onAdd(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withAlpha(22),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? AppColors.primary.withAlpha(80) : AppColors.slate200,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CronPreset extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onTap;

  const _CronPreset({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      avatar: const Icon(Icons.access_time, size: 14),
      onPressed: () => onTap(value),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _extractTaskSaveError(dynamic error, String fallback) {
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
