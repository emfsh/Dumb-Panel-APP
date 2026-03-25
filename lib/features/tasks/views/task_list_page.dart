import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/task.dart';
import '../../../shared/utils/api_utils.dart';
import '../providers/task_provider.dart';

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskStatusFilter {
  final String label;
  final String? value;

  const _TaskStatusFilter(this.label, this.value);
}

const _taskStatusFilters = [
  _TaskStatusFilter('全部', null),
  _TaskStatusFilter('运行中', '2'),
  _TaskStatusFilter('排队中', '0.5'),
  _TaskStatusFilter('已启用', '1'),
  _TaskStatusFilter('已禁用', '0'),
];

class _TaskListPageState extends ConsumerState<TaskListPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(taskProvider.notifier).load(refresh: true));
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(taskProvider.notifier).loadMore();
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

  Future<void> _showActionError(dynamic error, String fallback) async {
    _showMessage(_extractTaskError(error, fallback));
  }

  Future<void> _openLatestLog(Task task) async {
    if (task.isRunning) {
      _openLiveLog(task);
      return;
    }
    try {
      final latestLog = await ref
          .read(taskProvider.notifier)
          .fetchLatestLog(task.id);
      if (!mounted) {
        return;
      }
      if (latestLog == null) {
        _showMessage('当前任务暂无日志');
        return;
      }
      context.push('/logs/${latestLog.id}/stream');
    } catch (_) {
      _showMessage('打开日志失败');
    }
  }

  void _openLiveLog(Task task) {
    context.push('/tasks/${task.id}/live-logs', extra: task.name);
  }

  Future<void> _runTask(Task task) async {
    try {
      await ref.read(taskProvider.notifier).runTask(task.id);
      if (!mounted) {
        return;
      }
      _openLiveLog(task);
    } catch (error) {
      final message = _extractTaskError(error, '启动任务失败');
      if (!mounted) {
        return;
      }
      if (message.contains('运行中')) {
        _openLiveLog(task);
        return;
      }
      _showMessage(message);
    }
  }

  Future<void> _stopTask(Task task) async {
    try {
      await ref.read(taskProvider.notifier).stopTask(task.id);
      _showMessage('任务已停止');
    } catch (error) {
      await _showActionError(error, '停止任务失败');
    }
  }

  Future<void> _toggleTaskEnabled(Task task) async {
    try {
      if (task.isDisabled) {
        await ref.read(taskProvider.notifier).enableTask(task.id);
        _showMessage('任务已启用');
      } else {
        await ref.read(taskProvider.notifier).disableTask(task.id);
        _showMessage(task.isRunning ? '任务已设置为完成后禁用' : '任务已禁用');
      }
    } catch (error) {
      await _showActionError(error, '更新任务状态失败');
    }
  }

  Future<void> _copyTask(Task task) async {
    try {
      await ref.read(taskProvider.notifier).copyTask(task.id);
      _showMessage('任务已复制');
    } catch (error) {
      await _showActionError(error, '复制任务失败');
    }
  }

  Future<void> _togglePinned(Task task) async {
    try {
      if (task.isPinned) {
        await ref.read(taskProvider.notifier).unpinTask(task.id);
        _showMessage('已取消置顶');
      } else {
        await ref.read(taskProvider.notifier).pinTask(task.id);
        _showMessage('已置顶任务');
      }
    } catch (error) {
      await _showActionError(error, '更新置顶状态失败');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskProvider);
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '定时任务',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/tasks/new'),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索任务名称或命令...',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.slate400,
                  ),
                  filled: true,
                  fillColor: isLight ? Colors.white : AppColors.slate900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isLight ? AppColors.slate200 : AppColors.slate800,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isLight ? AppColors.slate200 : AppColors.slate800,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            size: 16,
                            color: AppColors.slate400,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                            ref.read(taskProvider.notifier).setKeyword('');
                          },
                        )
                      : null,
                ),
                style: const TextStyle(fontSize: 14),
                onChanged: (value) {
                  setState(() {});
                  ref.read(taskProvider.notifier).setKeyword(value);
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _taskStatusFilters.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final filter = _taskStatusFilters[index];
                  final selected = state.statusFilter == filter.value;
                  return ChoiceChip(
                    label: Text(filter.label),
                    selected: selected,
                    onSelected: (_) => ref
                        .read(taskProvider.notifier)
                        .setStatusFilter(filter.value),
                    selectedColor: AppColors.primary.withAlpha(18),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary.withAlpha(90)
                          : AppColors.slate200,
                    ),
                    labelStyle: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.primary : null,
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '共 ${state.total} 个任务',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (state.statusFilter != null)
                    TextButton(
                      onPressed: () =>
                          ref.read(taskProvider.notifier).setStatusFilter(null),
                      child: const Text('清除筛选'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () =>
                    ref.read(taskProvider.notifier).load(refresh: true),
                child: state.loading && state.tasks.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : state.tasks.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: state.tasks.length,
                        itemBuilder: (_, index) {
                          final task = state.tasks[index];
                          return _TaskCard(
                            task: task,
                            isLight: isLight,
                            onTap: () => _openLatestLog(task),
                            onRun: () => _runTask(task),
                            onStop: () => _stopTask(task),
                            onToggleEnabled: () => _toggleTaskEnabled(task),
                            onCopy: () => _copyTask(task),
                            onTogglePinned: () => _togglePinned(task),
                            onEdit: () =>
                                context.push('/tasks/edit', extra: task),
                            onDelete: () => _confirmDelete(task),
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

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: AppColors.slate400.withAlpha(120),
          ),
          const SizedBox(height: 12),
          const Text(
            '暂无任务',
            style: TextStyle(color: AppColors.slate400, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定要删除「${task.name}」吗？'),
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
    if (confirm != true) {
      return;
    }
    try {
      await ref.read(taskProvider.notifier).deleteTask(task.id);
      _showMessage('任务已删除');
    } catch (error) {
      await _showActionError(error, '删除任务失败');
    }
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final bool isLight;
  final VoidCallback onTap;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final VoidCallback onToggleEnabled;
  final VoidCallback onCopy;
  final VoidCallback onTogglePinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.isLight,
    required this.onTap,
    required this.onRun,
    required this.onStop,
    required this.onToggleEnabled,
    required this.onCopy,
    required this.onTogglePinned,
    required this.onEdit,
    required this.onDelete,
  });

  Color _dotColor() {
    if (task.isRunning) {
      return AppColors.primary;
    }
    if (task.isQueued) {
      return AppColors.amber500;
    }
    if (task.lastRunStatus == 1) {
      return AppColors.red500;
    }
    if (task.isEnabled) {
      return AppColors.primary;
    }
    return AppColors.slate300;
  }

  String _statusLabel() {
    if (task.isRunning) {
      return '运行中';
    }
    if (task.isQueued) {
      return '排队中';
    }
    if (task.isEnabled) {
      return '已启用';
    }
    return '已禁用';
  }

  Color _statusBg() {
    if (task.isRunning) {
      return isLight ? AppColors.primaryLight : AppColors.primary.withAlpha(25);
    }
    if (task.isQueued) {
      return AppColors.amber500.withAlpha(isLight ? 18 : 25);
    }
    if (task.isEnabled) {
      return isLight ? AppColors.blue100 : AppColors.blue500.withAlpha(25);
    }
    return isLight ? AppColors.slate100 : AppColors.slate800;
  }

  Color _statusFg() {
    if (task.isRunning) {
      return isLight ? const Color(0xFF047857) : AppColors.primary;
    }
    if (task.isQueued) {
      return AppColors.amber500;
    }
    if (task.isEnabled) {
      return isLight ? AppColors.blue600 : AppColors.blue500;
    }
    return AppColors.slate500;
  }

  String _taskTypeLabel() {
    switch (task.taskType) {
      case 'manual':
        return '手动运行';
      case 'startup':
        return '开机运行';
      default:
        return 'Cron';
    }
  }

  String _scheduleText() {
    if (task.taskType == 'cron' && task.cronExpression.trim().isNotEmpty) {
      return task.cronExpression;
    }
    return _taskTypeLabel();
  }

  String _bottomText() {
    if (task.isRunning) {
      return '点击查看实时日志';
    }
    if (task.lastRunStatus == 1 && task.lastRunAt != null) {
      final fmt = DateFormat('MM-dd HH:mm');
      return '上次失败：${fmt.format(task.lastRunAt!.toLocal())}';
    }
    if (task.nextRunAt != null) {
      final fmt = DateFormat('MM-dd HH:mm');
      return '下次运行：${fmt.format(task.nextRunAt!.toLocal())}';
    }
    if (task.taskType == 'manual') {
      return '手动触发';
    }
    if (task.taskType == 'startup') {
      return '面板启动时自动执行';
    }
    return '暂无计划';
  }

  Future<void> _showActionMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                task.isDisabled
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
              ),
              title: Text(task.isDisabled ? '启用任务' : '禁用任务'),
              onTap: () => Navigator.pop(sheetContext, 'toggle'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制任务'),
              onTap: () => Navigator.pop(sheetContext, 'copy'),
            ),
            ListTile(
              leading: Icon(
                task.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(task.isPinned ? '取消置顶' : '置顶任务'),
              onTap: () => Navigator.pop(sheetContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑任务'),
              onTap: () => Navigator.pop(sheetContext, 'edit'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.red500,
              ),
              title: const Text(
                '删除任务',
                style: TextStyle(color: AppColors.red500),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null) {
      return;
    }

    switch (action) {
      case 'toggle':
        onToggleEnabled();
        return;
      case 'copy':
        onCopy();
        return;
      case 'pin':
        onTogglePinned();
        return;
      case 'edit':
        onEdit();
        return;
      case 'delete':
        onDelete();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = _dotColor();
    final borderColor = isLight ? AppColors.slate200 : AppColors.slate800;
    final labels = task.labelsForDisplay;
    final hasFailure = task.lastRunStatus == 1;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActionMenu(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFailure ? AppColors.red500.withAlpha(60) : borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withAlpha(140),
                        blurRadius: task.isRunning || hasFailure ? 8 : 0,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          task.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (task.isPinned) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.push_pin,
                          size: 15,
                          color: AppColors.amber500,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusBg(),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _statusFg(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _scheduleText(),
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: isLight ? AppColors.slate600 : AppColors.slate400,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: task.taskType == 'cron'
                      ? Icons.schedule_outlined
                      : task.taskType == 'manual'
                      ? Icons.touch_app_outlined
                      : Icons.power_settings_new_outlined,
                  label: _taskTypeLabel(),
                ),
                ...labels.take(3).map((label) => _MetaChip(label: label)),
                if (labels.length > 3)
                  _MetaChip(label: '+${labels.length - 3}'),
                if ((task.notificationChannelName?.trim().isNotEmpty ?? false))
                  _MetaChip(
                    icon: Icons.notifications_active_outlined,
                    label: task.notificationChannelName!,
                    active: task.notificationChannelEnabled != false,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isLight
                        ? AppColors.slate100
                        : AppColors.slate800.withAlpha(120),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _bottomText(),
                      style: TextStyle(
                        fontSize: 12,
                        color: hasFailure
                            ? AppColors.red500
                            : (isLight
                                  ? AppColors.slate500
                                  : AppColors.slate400),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SmallIconBtn(
                    icon: task.isRunning ? Icons.stop : Icons.play_arrow,
                    onTap: task.isRunning ? onStop : onRun,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  _SmallIconBtn(
                    icon: task.isDisabled
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                    onTap: onToggleEnabled,
                    color: task.isDisabled
                        ? AppColors.primary
                        : AppColors.amber500,
                  ),
                  const SizedBox(width: 4),
                  _SmallIconBtn(icon: Icons.edit_outlined, onTap: onEdit),
                  const SizedBox(width: 4),
                  _SmallIconBtn(
                    icon: Icons.more_vert,
                    onTap: () => _showActionMenu(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool active;

  const _MetaChip({this.icon, required this.label, this.active = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final background = active
        ? (isLight ? AppColors.slate50 : AppColors.slate800)
        : (isLight ? AppColors.slate100 : AppColors.slate900);
    final foreground = active
        ? (isLight ? AppColors.slate700 : AppColors.slate300)
        : AppColors.slate400;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLight ? AppColors.slate200 : AppColors.slate800,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color ?? AppColors.slate400),
      ),
    );
  }
}

class TaskLiveLogPage extends ConsumerStatefulWidget {
  final int taskId;
  final String? taskName;

  const TaskLiveLogPage({super.key, required this.taskId, this.taskName});

  @override
  ConsumerState<TaskLiveLogPage> createState() => _TaskLiveLogPageState();
}

class _TaskLiveLogPageState extends ConsumerState<TaskLiveLogPage> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  List<String> _logs = [];
  bool _loading = true;
  bool _done = false;
  bool _loadingFinalLog = false;
  int _finalLogAttempts = 0;
  double? _status;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadLogs);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _loadLogs());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    try {
      final resp = await DioClient.instance.dio.get(
        ApiEndpoints.taskLiveLogs(widget.taskId),
      );
      final data = extractData(resp.data);
      final logs = data is Map && data['logs'] is List
          ? (data['logs'] as List)
                .map((e) => e.toString())
                .where((line) => line.trim().isNotEmpty)
                .toList()
          : <String>[];
      final done = data is Map && data['done'] == true;
      final status = data is Map && data['status'] is num
          ? (data['status'] as num).toDouble()
          : null;

      if (!mounted) {
        return;
      }

      setState(() {
        _logs = logs;
        _done = done;
        _status = status;
        _loading = false;
      });

      if (_done) {
        _timer?.cancel();
        if (!_loadingFinalLog) {
          _loadingFinalLog = true;
          unawaited(_loadCompletedLogSnapshot());
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _loadCompletedLogSnapshot() async {
    try {
      final resp = await DioClient.instance.dio.get(
        ApiEndpoints.taskLatestLog(widget.taskId),
      );
      final data = extractData(resp.data);
      if (data is! Map) {
        return;
      }
      final payload = Map<String, dynamic>.from(data);
      final content = payload['content']?.toString() ?? '';
      final historyLines = _splitLines(content);
      if (!mounted) {
        return;
      }
      if (historyLines.isEmpty) {
        if (_finalLogAttempts < 3) {
          _finalLogAttempts++;
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await _loadCompletedLogSnapshot();
          }
        }
        return;
      }
      setState(() {
        _logs = historyLines;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (_) {
      // 兜底保持实时页当前内容，避免影响已结束态展示
    }
  }

  List<String> _splitLines(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.taskName?.trim().isNotEmpty ?? false)
        ? '${widget.taskName} 运行日志'
        : '运行日志';

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _logs.isEmpty
                ? Center(
                    child: Text(
                      _done && _loadingFinalLog
                          ? '任务已结束，正在加载完整日志...'
                          : (_done ? '当前没有实时输出' : '正在等待任务输出...'),
                      style: const TextStyle(color: Color(0xFFD4D4D4)),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (_, index) => Text(
                      _logs[index],
                      style: const TextStyle(
                        color: Color(0xFFD4D4D4),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF252526),
            child: Text(
              _done
                  ? (_loadingFinalLog ? '任务已结束，正在回填完整日志' : '任务已结束')
                  : (_status == 2 ? '运行中，如缺依赖会在这里显示自动安装过程' : '任务启动中'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String _extractTaskError(dynamic error, String fallback) {
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
