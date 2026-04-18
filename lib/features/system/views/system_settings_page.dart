import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/api_utils.dart';

class SystemSettingsPage extends ConsumerStatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  ConsumerState<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends ConsumerState<SystemSettingsPage> {
  Map<String, dynamic>? _versionInfo;
  Map<String, dynamic>? _updateInfo;
  bool _loading = true;
  bool _checking = false;
  bool _savingConfigs = false;

  // Task execution config controllers
  final _timeoutC = TextEditingController();
  final _concurrencyC = TextEditingController();
  final _logRetentionC = TextEditingController();
  final _logMaxSizeC = TextEditingController();
  final _randomDelayC = TextEditingController();
  final _fileSuffixC = TextEditingController();
  final _editorBackgroundColorC = TextEditingController();
  bool _autoInstallDeps = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timeoutC.dispose();
    _concurrencyC.dispose();
    _logRetentionC.dispose();
    _logMaxSizeC.dispose();
    _randomDelayC.dispose();
    _fileSuffixC.dispose();
    _editorBackgroundColorC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.dio.get(ApiEndpoints.systemVersion),
        DioClient.instance.dio.get(ApiEndpoints.configs),
      ]);
      final versionData = extractData(results[0].data);
      final configData = extractData(results[1].data);

      final configs = configData is Map<String, dynamic>
          ? configData
          : <String, dynamic>{};

      // Parse task execution configs
      _timeoutC.text = _getConfigValueAny(configs, [
        'command_timeout',
        'default_timeout',
      ], '86400');
      _concurrencyC.text = _getConfigValueAny(configs, [
        'max_concurrent_tasks',
        'max_concurrency',
      ], '5');
      _logRetentionC.text = _getConfigValue(configs, 'log_retention_days', '7');
      _logMaxSizeC.text = _getConfigValueAny(configs, [
        'max_log_content_size',
        'log_max_size',
      ], '102400');
      _randomDelayC.text = _getConfigValue(configs, 'random_delay', '0');
      _fileSuffixC.text = _getConfigValueAny(configs, [
        'random_delay_extensions',
        'file_suffix',
      ], 'js py');
      _editorBackgroundColorC.text = _getConfigValue(
        configs,
        'editor_background_color',
        '',
      );
      _autoInstallDeps =
          _getConfigValue(configs, 'auto_install_deps', 'false') == 'true';

      setState(() {
        _versionInfo = versionData is Map<String, dynamic> ? versionData : null;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _getConfigValue(
    Map<String, dynamic> configs,
    String key,
    String fallback,
  ) {
    final config = configs[key];
    if (config is Map<String, dynamic>) {
      return config['value']?.toString() ?? fallback;
    }
    return fallback;
  }

  String _getConfigValueAny(
    Map<String, dynamic> configs,
    List<String> keys,
    String fallback,
  ) {
    for (final key in keys) {
      final value = _getConfigValue(configs, key, '');
      if (value.trim().isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final resp = await DioClient.instance.dio.get(ApiEndpoints.checkUpdate);
      final data = extractData(resp.data);
      setState(() {
        _updateInfo = data is Map<String, dynamic> ? data : null;
        _checking = false;
      });
      if (_updateInfo != null && _updateInfo!['has_update'] == true) {
        if (mounted) _showUpdateDialog();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已是最新版本')));
        }
      }
    } catch (e) {
      setState(() => _checking = false);
      if (mounted) {
        String msg = '检查更新失败';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['error']?.toString() ?? msg;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _showUpdateDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前: ${_updateInfo?['current'] ?? ''}'),
            Text('最新: ${_updateInfo?['latest'] ?? ''}'),
            if ((_updateInfo?['release_notes'] ?? '')
                .toString()
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _updateInfo!['release_notes'].toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (_updateInfo?['auto_update_supported'] == true)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('稍后'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _doUpdate();
                      },
                      child: const Text('立即更新'),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('稍后'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _doUpdate() async {
    try {
      await DioClient.instance.dio.post(
        '${ApiEndpoints.baseApi}/system/update',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新已启动，面板将自动重启')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新失败')));
      }
    }
  }

  Future<void> _restart() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('重启面板'),
        content: const Text('确定要重启面板吗？所有运行中的任务将被中断。'),
        actions: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('取消'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.red500,
                    ),
                    child: const Text('重启'),
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
        await DioClient.instance.dio.post(
          '${ApiEndpoints.baseApi}/system/restart',
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('面板将在 2 秒后重启')));
        }
      } catch (_) {}
    }
  }

  Future<void> _saveTaskConfigs() async {
    setState(() => _savingConfigs = true);
    try {
      await DioClient.instance.dio.put(
        ApiEndpoints.configsBatch,
        data: {
          'configs': {
            'command_timeout': _timeoutC.text.trim(),
            'max_concurrent_tasks': _concurrencyC.text.trim(),
            'log_retention_days': _logRetentionC.text.trim(),
            'max_log_content_size': _logMaxSizeC.text.trim(),
            'random_delay': _randomDelayC.text.trim(),
            'random_delay_extensions': _fileSuffixC.text.trim(),
            'auto_install_deps': _autoInstallDeps ? 'true' : 'false',
            'editor_background_color': _editorBackgroundColorC.text.trim(),
          },
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败')));
      }
    }
    setState(() => _savingConfigs = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

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
                      '系统设置',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        children: [
                          // ── Version Info ──
                          if (_versionInfo != null) ...[
                            _SectionTitle('版本信息'),
                            _Card(
                              isLight: isLight,
                              child: Column(
                                children: [
                                  _KVRow(
                                    '版本',
                                    _versionInfo?['version']?.toString() ?? '',
                                    isLight,
                                  ),
                                  const Divider(height: 16),
                                  _KVRow(
                                    'API',
                                    _versionInfo?['api_version']?.toString() ??
                                        '',
                                    isLight,
                                  ),
                                  const Divider(height: 16),
                                  _KVRow(
                                    'Go',
                                    _versionInfo?['go_version']?.toString() ??
                                        '',
                                    isLight,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 40,
                              child: OutlinedButton.icon(
                                onPressed: _checking ? null : _checkUpdate,
                                icon: _checking
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.system_update, size: 16),
                                label: Text(
                                  _checking ? '检查中...' : '检查更新',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // ── Task Execution Settings ──
                          _SectionTitle('任务执行'),
                          const SizedBox(height: 8),
                          _Card(
                            isLight: isLight,
                            child: Column(
                              children: [
                                _ConfigField(
                                  label: '全局默认超时（秒）',
                                  hint: '单个任务未设超时时使用此值',
                                  controller: _timeoutC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '定时任务并发数',
                                  hint: '同时执行的最大任务数量',
                                  controller: _concurrencyC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '日志删除频率（天）',
                                  hint: '日志清理接口默认保留近多少天的数据',
                                  controller: _logRetentionC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '日志内容上限（字节）',
                                  hint: '单次任务在数据库中保留的日志字节数',
                                  controller: _logMaxSizeC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '随机延迟最大秒数',
                                  hint: '留空或 0 表示不延迟',
                                  controller: _randomDelayC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '延迟文件后缀',
                                  hint: '如 js py，空格分隔',
                                  controller: _fileSuffixC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                _ConfigField(
                                  label: '编辑器背景色',
                                  hint:
                                      '支持 #ffffff、#111827 或 rgba(...)，留空使用默认值',
                                  controller: _editorBackgroundColorC,
                                  isLight: isLight,
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '自动安装缺失依赖',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '脚本运行失败且检测到缺失依赖时自动安装',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isLight
                                                ? AppColors.slate500
                                                : AppColors.slate400,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Switch(
                                      value: _autoInstallDeps,
                                      onChanged: (v) =>
                                          setState(() => _autoInstallDeps = v),
                                      activeTrackColor: AppColors.primary.withAlpha(100),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton(
                              onPressed: _savingConfigs
                                  ? null
                                  : _saveTaskConfigs,
                              child: Text(_savingConfigs ? '保存中...' : '保存任务配置'),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ── System Operations ──
                          _SectionTitle('系统操作'),
                          const SizedBox(height: 8),
                          _ActionBtn(
                            icon: Icons.backup,
                            title: '数据备份与恢复',
                            subtitle: '创建备份、恢复、管理备份文件',
                            isLight: isLight,
                            onTap: () => context.push('/backup'),
                          ),
                          const SizedBox(height: 8),
                          _ActionBtn(
                            icon: Icons.restart_alt,
                            title: '重启面板',
                            subtitle: '重启面板服务',
                            isLight: isLight,
                            onTap: _restart,
                            danger: true,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final bool isLight;
  final Widget child;
  const _Card({required this.isLight, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColors.slate900,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLight ? AppColors.slate200 : AppColors.slate800,
        ),
      ),
      child: child,
    );
  }
}

class _KVRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLight;
  const _KVRow(this.label, this.value, this.isLight);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isLight ? AppColors.slate500 : AppColors.slate400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isLight;

  const _ConfigField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 11,
              color: isLight ? AppColors.slate400 : AppColors.slate500,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: const TextStyle(fontSize: 13),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: TextStyle(
            fontSize: 10,
            color: isLight ? AppColors.slate400 : AppColors.slate500,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLight;
  final VoidCallback onTap;
  final bool danger;

  const _ActionBtn({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLight,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColors.slate900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLight ? AppColors.slate200 : AppColors.slate800,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: danger ? AppColors.red500 : AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: danger ? AppColors.red500 : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isLight ? AppColors.slate500 : AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: isLight ? AppColors.slate400 : AppColors.slate600,
            ),
          ],
        ),
      ),
    );
  }
}
