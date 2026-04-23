import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/env_var.dart';
import '../../../shared/utils/api_utils.dart';

final envListProvider = StateNotifierProvider<EnvListNotifier, EnvListState>((
  ref,
) {
  return EnvListNotifier();
});

const _selectedGroupUnset = Object();

enum _EnvBatchAction { enable, disable, delete }

class EnvListState {
  final List<EnvVar> envs;
  final int total;
  final bool loading;
  final List<String> groups;
  final String? selectedGroup;
  final String keyword;

  const EnvListState({
    this.envs = const [],
    this.total = 0,
    this.loading = false,
    this.groups = const [],
    this.selectedGroup,
    this.keyword = '',
  });

  EnvListState copyWith({
    List<EnvVar>? envs,
    int? total,
    bool? loading,
    List<String>? groups,
    Object? selectedGroup = _selectedGroupUnset,
    String? keyword,
  }) {
    return EnvListState(
      envs: envs ?? this.envs,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      groups: groups ?? this.groups,
      selectedGroup: identical(selectedGroup, _selectedGroupUnset)
          ? this.selectedGroup
          : selectedGroup as String?,
      keyword: keyword ?? this.keyword,
    );
  }
}

class EnvListNotifier extends StateNotifier<EnvListState> {
  EnvListNotifier() : super(const EnvListState());

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final dio = DioClient.instance.dio;
      // The panel backend caps page_size at 100. Requesting a larger value
      // silently falls back to 20, which previously made the app stop after 40 rows.
      const pageSize = 100;
      final params = <String, dynamic>{'page': 1, 'page_size': pageSize};
      if (state.selectedGroup != null && state.selectedGroup!.isNotEmpty) {
        params['group'] = state.selectedGroup;
      }
      if (state.keyword.isNotEmpty) {
        params['keyword'] = state.keyword;
      }

      final firstPageFuture = dio.get(
        ApiEndpoints.envs,
        queryParameters: params,
      );
      final groupsFuture = dio.get(ApiEndpoints.envsGroups);
      final results = await Future.wait([firstPageFuture, groupsFuture]);

      final paginated = extractPaginated(results[0].data);
      final allItems = <Map<String, dynamic>>[...paginated.items];
      var page = 2;
      while (allItems.length < paginated.total) {
        final nextResponse = await dio.get(
          ApiEndpoints.envs,
          queryParameters: {...params, 'page': page},
        );
        final nextPage = extractPaginated(nextResponse.data);
        if (nextPage.items.isEmpty) {
          break;
        }
        allItems.addAll(nextPage.items);
        page++;
      }

      final items = allItems.map((e) => EnvVar.fromJson(e)).toList();
      final groupsRaw = results[1].data;
      List groupsList;
      if (groupsRaw is List) {
        groupsList = groupsRaw;
      } else if (groupsRaw is Map && groupsRaw['data'] is List) {
        groupsList = groupsRaw['data'] as List;
      } else {
        groupsList = [];
      }
      final groups = groupsList.map((e) => e.toString()).toList();
      state = state.copyWith(
        envs: items,
        total: paginated.total > items.length ? paginated.total : items.length,
        loading: false,
        groups: groups,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  void setGroup(String? group) {
    state = state.copyWith(selectedGroup: group);
    load();
  }

  void setKeyword(String keyword) {
    state = state.copyWith(keyword: keyword);
    load();
  }

  Future<void> toggle(int id, bool enabled) async {
    final dio = DioClient.instance.dio;
    if (enabled) {
      await dio.put(ApiEndpoints.envEnable(id));
    } else {
      await dio.put(ApiEndpoints.envDisable(id));
    }
    await load();
  }

  Future<void> delete(int id) async {
    await DioClient.instance.dio.delete(ApiEndpoints.envById(id));
    await load();
  }

  Future<void> batchDelete(List<int> ids) async {
    await DioClient.instance.dio.delete(
      ApiEndpoints.envsBatchDelete,
      data: {'ids': ids},
    );
    await load();
  }

  Future<void> batchEnable(List<int> ids) async {
    await DioClient.instance.dio.put(
      ApiEndpoints.envsBatchEnable,
      data: {'ids': ids},
    );
    await load();
  }

  Future<void> batchDisable(List<int> ids) async {
    await DioClient.instance.dio.put(
      ApiEndpoints.envsBatchDisable,
      data: {'ids': ids},
    );
    await load();
  }

  Future<void> batchSetGroup(List<int> ids, String group) async {
    await DioClient.instance.dio.put(
      ApiEndpoints.envsBatchGroup,
      data: {'ids': ids, 'group': group},
    );
    await load();
  }

  Future<void> create(
    String name,
    String value, {
    String remarks = '',
    String group = '',
  }) async {
    await DioClient.instance.dio.post(
      ApiEndpoints.envs,
      data: {'name': name, 'value': value, 'remarks': remarks, 'group': group},
    );
    await load();
  }

  Future<void> update(
    int id,
    String name,
    String value, {
    String remarks = '',
  }) async {
    await DioClient.instance.dio.put(
      ApiEndpoints.envById(id),
      data: {'name': name, 'value': value, 'remarks': remarks},
    );
    await load();
  }
}

class EnvListPage extends ConsumerStatefulWidget {
  const EnvListPage({super.key});

  @override
  ConsumerState<EnvListPage> createState() => _EnvListPageState();
}

class _EnvListPageState extends ConsumerState<EnvListPage> {
  final _searchController = TextEditingController();
  final Set<int> _selectedIds = <int>{};
  Timer? _debounce;

  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(envListProvider.notifier).load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _isSelected(int id) => _selectedIds.contains(id);

  bool _isAllSelected(List<EnvVar> envs) =>
      envs.isNotEmpty && envs.every((env) => _selectedIds.contains(env.id));

  void _setSelectionMode(bool enabled) {
    setState(() {
      _selectionMode = enabled;
      if (!enabled) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      _selectionMode = true;
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _enterSelectionModeWith(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelectAll(List<EnvVar> envs) {
    final visibleIds = envs.map((env) => env.id).toSet();
    setState(() {
      if (visibleIds.isNotEmpty &&
          visibleIds.every((id) => _selectedIds.contains(id))) {
        _selectedIds.removeAll(visibleIds);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  Future<bool> _confirmBatchDelete(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 $count 个环境变量吗？'),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(false),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(true),
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

    return confirmed == true;
  }

  Future<void> _performBatchAction(_EnvBatchAction action) async {
    final ids = _selectedIds.toList()..sort();
    if (ids.isEmpty) {
      return;
    }

    if (action == _EnvBatchAction.delete) {
      final confirmed = await _confirmBatchDelete(ids.length);
      if (!confirmed) {
        return;
      }
    }

    try {
      final notifier = ref.read(envListProvider.notifier);
      switch (action) {
        case _EnvBatchAction.enable:
          await notifier.batchEnable(ids);
          break;
        case _EnvBatchAction.disable:
          await notifier.batchDisable(ids);
          break;
        case _EnvBatchAction.delete:
          await notifier.batchDelete(ids);
          break;
      }

      if (!mounted) {
        return;
      }

      _setSelectionMode(false);
      final message = switch (action) {
        _EnvBatchAction.enable => '已批量启用 ${ids.length} 个环境变量',
        _EnvBatchAction.disable => '已批量禁用 ${ids.length} 个环境变量',
        _EnvBatchAction.delete => '已批量删除 ${ids.length} 个环境变量',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批量操作失败，请稍后重试')));
    }
  }

  Future<void> _performBatchGroup(String group) async {
    final ids = _selectedIds.toList()..sort();
    if (ids.isEmpty) {
      return;
    }

    try {
      await ref.read(envListProvider.notifier).batchSetGroup(ids, group);
      if (!mounted) {
        return;
      }

      _setSelectionMode(false);
      final message = group.trim().isEmpty
          ? '已清空 ${ids.length} 个环境变量的分组'
          : '已将 ${ids.length} 个环境变量分组到“${group.trim()}”';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批量分组失败，请稍后重试')));
    }
  }

  Future<void> _showBatchGroupDialog(List<String> groups) async {
    if (_selectedIds.isEmpty) {
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('批量分组'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('将已选择的 ${_selectedIds.length} 个环境变量设置到同一分组。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '分组名称',
                    hintText: '输入新分组或选择已有分组',
                  ),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '已有分组',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: groups
                        .map(
                          (group) => ActionChip(
                            label: Text(group),
                            onPressed: () {
                              controller.text = group;
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );
                              setDialogState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(''),
                      child: const Text('清空分组'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.of(dialogCtx).pop(controller.text.trim()),
                      child: const Text('确认'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    await _performBatchGroup(result);
  }

  Future<void> _refresh() async {
    if (_selectionMode) {
      _setSelectionMode(false);
    }
    await ref.read(envListProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(envListProvider);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final messenger = ScaffoldMessenger.of(context);
    final selectedCount = _selectedIds.length;
    final allSelected = _isAllSelected(state.envs);

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
                    '环境变量',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      _HeaderChipButton(
                        label: _selectionMode ? '取消' : '批量',
                        icon: _selectionMode ? Icons.close : Icons.done_all,
                        isLight: isLight,
                        onTap: () => _setSelectionMode(!_selectionMode),
                      ),
                      if (!_selectionMode) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showCreateDialog(),
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
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索变量...',
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.slate400,
                          ),
                          filled: true,
                          fillColor: isLight
                              ? Colors.white
                              : AppColors.slate900,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isLight
                                  ? AppColors.slate200
                                  : AppColors.slate800,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isLight
                                  ? AppColors.slate200
                                  : AppColors.slate800,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
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
                                    if (_selectionMode) {
                                      _setSelectionMode(false);
                                    }
                                    ref
                                        .read(envListProvider.notifier)
                                        .setKeyword('');
                                  },
                                )
                              : null,
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (v) {
                          setState(() {});
                          if (_selectionMode) {
                            _setSelectionMode(false);
                          }
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 300), () {
                            ref.read(envListProvider.notifier).setKeyword(v);
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isLight ? Colors.white : AppColors.slate900,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isLight
                            ? AppColors.slate200
                            : AppColors.slate800,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: state.selectedGroup,
                        hint: const Text('全部', style: TextStyle(fontSize: 13)),
                        isDense: true,
                        icon: const Icon(
                          Icons.expand_more,
                          size: 18,
                          color: AppColors.slate400,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部'),
                          ),
                          ...state.groups.map(
                            (g) => DropdownMenuItem<String?>(
                              value: g,
                              child: Text(g),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (_selectionMode) {
                            _setSelectionMode(false);
                          }
                          ref.read(envListProvider.notifier).setGroup(v);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectionMode) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.white : AppColors.slate900,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isLight ? AppColors.slate200 : AppColors.slate800,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '已选择 $selectedCount 项',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _toggleSelectAll(state.envs),
                            child: Text(allSelected ? '取消全选' : '全选'),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _BatchActionButton(
                            label: '批量分组',
                            icon: Icons.label_outline,
                            color: AppColors.blue500,
                            isLight: isLight,
                            enabled: selectedCount > 0,
                            onTap: () => _showBatchGroupDialog(state.groups),
                          ),
                          _BatchActionButton(
                            label: '批量启用',
                            icon: Icons.play_circle_outline,
                            color: AppColors.primary,
                            isLight: isLight,
                            enabled: selectedCount > 0,
                            onTap: () =>
                                _performBatchAction(_EnvBatchAction.enable),
                          ),
                          _BatchActionButton(
                            label: '批量禁用',
                            icon: Icons.pause_circle_outline,
                            color: AppColors.slate500,
                            isLight: isLight,
                            enabled: selectedCount > 0,
                            onTap: () =>
                                _performBatchAction(_EnvBatchAction.disable),
                          ),
                          _BatchActionButton(
                            label: '批量删除',
                            icon: Icons.delete_outline,
                            color: AppColors.red500,
                            isLight: isLight,
                            enabled: selectedCount > 0,
                            onTap: () =>
                                _performBatchAction(_EnvBatchAction.delete),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _refresh,
                child: state.loading && state.envs.isEmpty
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
                    : state.envs.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 100),
                          Icon(
                            Icons.key_off,
                            size: 56,
                            color: AppColors.slate400.withAlpha(120),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              '暂无环境变量',
                              style: TextStyle(color: AppColors.slate400),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: state.envs.length,
                        itemBuilder: (_, i) {
                          final env = state.envs[i];
                          return _EnvCard(
                            env: env,
                            isLight: isLight,
                            selectionMode: _selectionMode,
                            selected: _isSelected(env.id),
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelection(env.id);
                              } else {
                                _showDetailSheet(env);
                              }
                            },
                            onLongPress: () {
                              if (!_selectionMode) {
                                _enterSelectionModeWith(env.id);
                              }
                            },
                            onSelectedChanged: () => _toggleSelection(env.id),
                            onCopy: () {
                              Clipboard.setData(ClipboardData(text: env.value));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制值')),
                              );
                            },
                            onToggle: () async {
                              await ref
                                  .read(envListProvider.notifier)
                                  .toggle(env.id, !env.enabled);
                              if (!mounted) {
                                return;
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    env.enabled
                                        ? '已禁用 ${env.name}'
                                        : '已启用 ${env.name}',
                                  ),
                                ),
                              );
                            },
                            onEdit: () => _showDetailSheet(env),
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

  void _showDetailSheet(EnvVar env) {
    final messenger = ScaffoldMessenger.of(context);
    final nameC = TextEditingController(text: env.name);
    final valueC = TextEditingController(text: env.value);
    final remarksC = TextEditingController(text: env.remarks);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final navigator = Navigator.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (env.enabled ? AppColors.primary : AppColors.slate400)
                              .withAlpha(18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      env.enabled ? '当前已启用' : '当前已禁用',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: env.enabled
                            ? AppColors.primary
                            : AppColors.slate500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(envListProvider.notifier)
                          .toggle(env.id, !env.enabled);
                      if (!mounted) {
                        return;
                      }
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            env.enabled ? '已禁用 ${env.name}' : '已启用 ${env.name}',
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      env.enabled
                          ? Icons.pause_circle_outline
                          : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(env.enabled ? '禁用' : '启用'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: env.enabled
                          ? AppColors.slate600
                          : AppColors.primary,
                      side: BorderSide(
                        color: env.enabled
                            ? AppColors.slate300
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                env.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '变量名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueC,
                decoration: const InputDecoration(labelText: '值'),
                maxLines: 4,
                minLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksC,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('关闭'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: valueC.text));
                        ScaffoldMessenger.of(
                          ctx,
                        ).showSnackBar(const SnackBar(content: Text('已复制值')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.blue500,
                        side: const BorderSide(color: AppColors.blue500),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        ref
                            .read(envListProvider.notifier)
                            .update(
                              env.id,
                              nameC.text.trim(),
                              valueC.text,
                              remarks: remarksC.text.trim(),
                            );
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('已保存')));
                      },
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('保存'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).then((_) {
      nameC.dispose();
      valueC.dispose();
      remarksC.dispose();
    });
  }

  void _showCreateDialog() {
    final nameC = TextEditingController();
    final valueC = TextEditingController();
    final remarksC = TextEditingController();
    final groupC = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新建环境变量',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: '变量名', hintText: '如 MY_TOKEN'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueC,
                decoration: const InputDecoration(labelText: '值'),
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: remarksC,
                      decoration: const InputDecoration(labelText: '备注'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: groupC,
                      decoration: const InputDecoration(labelText: '分组'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (nameC.text.trim().isEmpty) return;
                  ref.read(envListProvider.notifier).create(
                    nameC.text.trim(),
                    valueC.text,
                    remarks: remarksC.text.trim(),
                    group: groupC.text.trim(),
                  );
                  Navigator.of(ctx).pop();
                },
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      nameC.dispose();
      valueC.dispose();
      remarksC.dispose();
      groupC.dispose();
    });
  }
}

class _HeaderChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLight;
  final VoidCallback onTap;

  const _HeaderChipButton({
    required this.label,
    required this.icon,
    required this.isLight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isLight ? AppColors.slate200 : AppColors.slate800,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.slate400),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLight;
  final bool enabled;
  final VoidCallback onTap;

  const _BatchActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLight,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = enabled
        ? (isLight ? color.withAlpha(18) : color.withAlpha(24))
        : (isLight ? AppColors.slate50 : AppColors.slate800);
    final borderColor = enabled
        ? color.withAlpha(isLight ? 60 : 90)
        : (isLight ? AppColors.slate200 : AppColors.slate700);
    final foregroundColor = enabled ? color : AppColors.slate400;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvCard extends StatelessWidget {
  final EnvVar env;
  final bool isLight;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelectedChanged;
  final VoidCallback onCopy;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  const _EnvCard({
    required this.env,
    required this.isLight,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectedChanged,
    required this.onCopy,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isLight ? AppColors.slate200 : AppColors.slate800),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onSelectedChanged(),
                      activeColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: env.enabled ? AppColors.primary : AppColors.slate300,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    env.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isLight ? AppColors.blue600 : AppColors.blue500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!selectionMode) ...[
                  _MiniBtn(icon: Icons.copy_outlined, isLight: isLight, onTap: onCopy),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onToggle,
                    child: Icon(
                      env.enabled ? Icons.toggle_on : Icons.toggle_off_outlined,
                      size: 32,
                      color: env.enabled ? AppColors.primary : AppColors.slate400,
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: EdgeInsets.only(left: selectionMode ? 32 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    env.value.replaceAll('\n', ' '),
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: isLight ? AppColors.slate500 : AppColors.slate400,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (env.remarks.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      env.remarks,
                      style: TextStyle(
                        fontSize: 10,
                        color: isLight ? AppColors.slate400 : AppColors.slate500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final bool isLight;
  final Color? color;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.icon,
    required this.isLight,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isLight ? AppColors.slate50 : AppColors.slate800,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: color ?? AppColors.slate400),
      ),
    );
  }
}
