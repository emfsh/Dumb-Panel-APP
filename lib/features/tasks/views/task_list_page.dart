import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/sse_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/task.dart';
import '../../../shared/utils/api_utils.dart';
import '../../../shared/widgets/task_cron_list.dart';
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
  Timer? _debounce;

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

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.jumpTo(0);
      }
      ref.read(taskProvider.notifier).setKeyword(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
                onChanged: _onSearchChanged,
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
                    onSelected: (_) {
                      if (_scrollController.hasClients && _scrollController.offset > 0) {
                        _scrollController.jumpTo(0);
                      }
                      ref
                          .read(taskProvider.notifier)
                          .setStatusFilter(filter.value);
                    },
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
                      onPressed: () {
                        if (_scrollController.hasClients && _scrollController.offset > 0) {
                          _scrollController.jumpTo(0);
                        }
                        ref.read(taskProvider.notifier).setStatusFilter(null);
                      },
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
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      )
                    : state.tasks.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [_buildEmpty()],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
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
    final scriptPath = _extractScriptPathFromCommand(task.command);
    var deleteScript = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('删除任务'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要删除「${task.name}」吗？'),
              if (scriptPath != null) ...[
                const SizedBox(height: 14),
                CheckboxListTile(
                  value: deleteScript,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('同时删除关联脚本'),
                  subtitle: Text(scriptPath),
                  onChanged: (value) {
                    setDialogState(() => deleteScript = value ?? false);
                  },
                ),
              ],
            ],
          ),
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
      ),
    );
    if (confirm != true) {
      return;
    }
    try {
      await ref.read(taskProvider.notifier).deleteTask(task.id);
      if (deleteScript && scriptPath != null) {
        try {
          await DioClient.instance.dio.delete(
            ApiEndpoints.scripts,
            queryParameters: {'path': scriptPath, 'type': 'file'},
          );
          _showMessage('任务和关联脚本已删除');
        } catch (error) {
          _showMessage('任务已删除，但脚本删除失败：${extractErrorMessage(error, '请稍后手动删除脚本')}');
        }
        return;
      }
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
        return '常规定时';
    }
  }

  List<String> _scheduleExpressions() {
    if (task.cronExpressions.isNotEmpty) {
      return task.cronExpressions;
    }
    if (task.cronExpression.trim().isNotEmpty) {
      return [task.cronExpression.trim()];
    }
    return const [];
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(14),
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
                    boxShadow: task.isRunning || hasFailure
                        ? [BoxShadow(color: dotColor.withAlpha(140), blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.isPinned)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.push_pin, size: 14, color: AppColors.amber500),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusBg(),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _statusFg()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  task.taskType == 'cron' ? Icons.schedule_outlined
                      : task.taskType == 'manual' ? Icons.touch_app_outlined
                      : Icons.power_settings_new_outlined,
                  size: 12,
                  color: isLight ? AppColors.slate400 : AppColors.slate500,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: task.taskType == 'cron'
                      ? TaskCronList(
                          expressions: _scheduleExpressions(),
                          compact: true,
                        )
                      : Text(
                          _taskTypeLabel(),
                          style: TextStyle(
                            fontSize: 12,
                            color: isLight
                                ? AppColors.slate500
                                : AppColors.slate400,
                          ),
                        ),
                ),
              ],
            ),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...labels.take(3).map((label) => _MetaChip(label: label)),
                  if (labels.length > 3) _MetaChip(label: '+${labels.length - 3}'),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _bottomText(),
                    style: TextStyle(
                      fontSize: 11,
                      color: hasFailure ? AppColors.red500 : (isLight ? AppColors.slate400 : AppColors.slate500),
                    ),
                  ),
                ),
                _SmallIconBtn(
                  icon: task.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  onTap: task.isRunning ? onStop : onRun,
                  color: task.isRunning ? AppColors.red500 : AppColors.primary,
                ),
                const SizedBox(width: 6),
                _SmallIconBtn(
                  icon: task.isDisabled ? Icons.toggle_on_outlined : Icons.toggle_off_outlined,
                  onTap: onToggleEnabled,
                  color: task.isDisabled ? AppColors.primary : AppColors.slate400,
                ),
                const SizedBox(width: 6),
                _SmallIconBtn(icon: Icons.edit_outlined, onTap: onEdit),
                const SizedBox(width: 6),
                _SmallIconBtn(icon: Icons.more_horiz, onTap: () => _showActionMenu(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _extractScriptPathFromCommand(String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final tokens = _splitCommandTokens(trimmed);
  if (tokens.isEmpty) {
    return null;
  }

  bool hasSupportedExtension(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.py') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.go');
  }

  String? joinCandidate(List<String> items) {
    for (var count = items.length; count >= 1; count--) {
      final candidate = items.take(count).join(' ').trim();
      if (hasSupportedExtension(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  switch (tokens.first) {
    case 'task':
    case 'desi':
      final rest = tokens.sublist(1);
      var idx = 0;
      while (idx < rest.length) {
        if (rest[idx] == '-m' && idx + 1 < rest.length) {
          idx += 2;
          continue;
        }
        if (rest[idx] == '-l') {
          idx += 1;
          continue;
        }
        break;
      }
      return joinCandidate(rest.sublist(idx));
    case 'python':
    case 'python3':
    case 'node':
    case 'ts-node':
    case 'bash':
    case 'go':
      if (tokens.length <= 1) {
        return null;
      }
      return joinCandidate(tokens.sublist(1));
    default:
      return null;
  }
}

List<String> _splitCommandTokens(String command) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  String? quote;

  for (final rune in command.runes) {
    final char = String.fromCharCode(rune);
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }

    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }

    if (char.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }

    buffer.write(char);
  }

  if (buffer.isNotEmpty) {
    tokens.add(buffer.toString());
  }

  return tokens;
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
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final btnColor = color ?? AppColors.slate400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: btnColor.withAlpha(isLight ? 16 : 22),
          shape: BoxShape.circle,
          border: Border.all(
            color: btnColor.withAlpha(isLight ? 40 : 50),
          ),
        ),
        child: Icon(icon, size: 18, color: btnColor),
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

class TaskDetailSheet extends StatelessWidget {
  final Task task;

  const TaskDetailSheet({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final labels = task.labelsForDisplay;
    final scheduleExpressions = task.cronExpressions.isNotEmpty
        ? task.cronExpressions
        : (task.cronExpression.trim().isNotEmpty ? [task.cronExpression.trim()] : const <String>[]);

    Widget infoTile(String label, Widget child, {bool expand = false}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isLight ? AppColors.slate100 : AppColors.slate800,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (expand) child else DefaultTextStyle.merge(child: child),
          ],
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '任务详情',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                task.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      infoTile(
                        '状态',
                        _MetaChip(label: task.statusText, active: !task.isDisabled),
                      ),
                      infoTile(
                        '任务类型',
                        Text(
                          task.taskType == 'manual'
                              ? '手动运行'
                              : task.taskType == 'startup'
                                  ? '开机运行'
                                  : '常规定时',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      infoTile(
                        '定时规则',
                        task.taskType == 'cron'
                            ? TaskCronList(expressions: scheduleExpressions)
                            : Text(
                                '不使用 Cron',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                        expand: true,
                      ),
                      infoTile(
                        '执行命令',
                        SelectableText(
                          task.command,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            fontFamily: 'monospace',
                          ),
                        ),
                        expand: true,
                      ),
                      infoTile(
                        '标签',
                        labels.isEmpty
                            ? Text(
                                '无',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: labels
                                    .map((label) => _MetaChip(label: label))
                                    .toList(),
                              ),
                        expand: true,
                      ),
                      infoTile(
                        '上次运行',
                        Text(
                          task.lastRunAt == null
                              ? '-'
                              : DateFormat('yyyy-MM-dd HH:mm:ss').format(task.lastRunAt!.toLocal()),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      infoTile(
                        '下次运行',
                        Text(
                          task.nextRunAt == null
                              ? '-'
                              : DateFormat('yyyy-MM-dd HH:mm:ss').format(task.nextRunAt!.toLocal()),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      infoTile(
                        '上次结果',
                        Text(
                          task.lastRunStatus == null
                              ? '未运行'
                              : task.lastRunStatus == 0
                                  ? '成功'
                                  : '失败',
                          style: TextStyle(
                            fontSize: 13,
                            color: task.lastRunStatus == 1 ? AppColors.red500 : null,
                          ),
                        ),
                      ),
                      infoTile(
                        '最近耗时',
                        Text(
                          task.lastRunningTime == null
                              ? '-'
                              : '${task.lastRunningTime!.toStringAsFixed(2)}s',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskLiveLogPageState extends ConsumerState<TaskLiveLogPage> {
  final ScrollController _scrollController = ScrollController();
  final _sseClient = SseClient();
  final _lines = <String>[];
  bool _loading = true;
  bool _done = false;
  bool _autoScroll = true;
  String _statusText = '连接中...';

  @override
  void initState() {
    super.initState();
    Future.microtask(_init);
  }

  @override
  void dispose() {
    _sseClient.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final resp = await DioClient.instance.dio.get(
        ApiEndpoints.taskLatestLog(widget.taskId),
      );
      final data = extractData(resp.data);
      if (data is Map<String, dynamic>) {
        final logId = (data['id'] as num?)?.toInt();
        final content = data['content']?.toString() ?? '';
        final isRunning = data['status'] == 0 || data['status'] == null;

        if (content.isNotEmpty) {
          final lines = content.replaceAll('\r\n', '\n').split('\n');
          if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
          _lines.addAll(lines);
        }

        if (mounted) {
          setState(() {
            _loading = false;
            _done = !isRunning;
            _statusText = isRunning ? '运行中' : '已完成';
          });
        }

        if (isRunning && logId != null) {
          _connectSSE(logId);
        }
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() { _loading = false; _statusText = '等待日志...'; });
    _pollUntilLogReady();
  }

  void _pollUntilLogReady() {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || _done) return;
      try {
        final resp = await DioClient.instance.dio.get(
          ApiEndpoints.taskLatestLog(widget.taskId),
        );
        final data = extractData(resp.data);
        if (data is Map<String, dynamic> && data['id'] != null) {
      final content = data['content']?.toString() ?? '';
      final isRunning = data['status'] == 0 || data['status'] == null;

          if (content.isNotEmpty) {
            final lines = content.replaceAll('\r\n', '\n').split('\n');
            if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
            if (mounted) setState(() => _lines.addAll(lines));
          }

        if (isRunning) {
          _connectSSE(widget.taskId);
          if (_autoScroll) {
            _scrollToBottom();
          }
        } else if (mounted) {
          setState(() { _done = true; _statusText = '已完成'; });
        }
        return;
        }
      } catch (_) {}
      _pollUntilLogReady();
    });
  }

  void _connectSSE(int logId) {
    _sseClient.connect(
      path: ApiEndpoints.logStream(logId),
      autoReconnect: true,
      onEvent: (event) {
        if (!mounted) return;
        if (event.event == 'done') {
          setState(() { _done = true; _statusText = '已完成'; });
          return;
        }
        final newLines = event.data.replaceAll('\r\n', '\n').split('\n');
        newLines.removeWhere((l) => l.isEmpty);
        if (newLines.isEmpty) return;
        setState(() {
          _lines.addAll(newLines);
          _statusText = '运行中';
        });
        if (_autoScroll) _scrollToBottom();
      },
      onDone: () {
        if (mounted) setState(() { _done = true; _statusText = '连接结束'; });
      },
      onError: (_) {
        if (mounted) setState(() { _done = true; _statusText = '连接错误'; });
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              label: Text(_statusText, style: const TextStyle(fontSize: 11)),
              avatar: _done
                  ? const Icon(Icons.check, size: 14)
                  : const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              color: _autoScroll ? AppColors.primary : Colors.white70,
            ),
            tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
              if (_autoScroll) _scrollToBottom();
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1E1E1E),
        child: _loading && _lines.isEmpty
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _lines.isEmpty
            ? Center(
                child: Text(
                  _done ? '无日志内容' : '等待日志输出...',
                  style: const TextStyle(color: Color(0xFFD4D4D4)),
                ),
              )
            : Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: TextSelectionThemeData(
                    selectionColor: AppColors.primary.withAlpha(80),
                    selectionHandleColor: AppColors.primary,
                  ),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _lines.join('\n'),
                      style: const TextStyle(
                        color: Color(0xFFD4D4D4),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

String _extractTaskError(dynamic error, String fallback) =>
    extractErrorMessage(error, fallback);
