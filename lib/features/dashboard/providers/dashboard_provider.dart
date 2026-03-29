import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/utils/api_utils.dart';

String _formatBytes(dynamic bytes) {
  if (bytes == null) return '-';
  final b = (bytes as num).toDouble();
  if (b < 1024) return '${b.toStringAsFixed(0)}B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
  if (b < 1024 * 1024 * 1024)
    return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
}

class DashboardData {
  final Map<String, dynamic> system;
  final Map<String, dynamic> dashboard;
  final bool loading;
  final String? error;

  const DashboardData({
    this.system = const {},
    this.dashboard = const {},
    this.loading = false,
    this.error,
  });

  // 系统资源
  double get cpuUsage => (system['cpu_usage'] as num?)?.toDouble() ?? 0;
  double get memoryUsage => (system['memory_usage'] as num?)?.toDouble() ?? 0;
  double get diskUsage => (system['disk_usage'] as num?)?.toDouble() ?? 0;
  String get memoryTotal => _formatBytes(system['memory_total']);
  String get memoryUsed => _formatBytes(system['memory_used']);
  String get diskTotal => _formatBytes(system['disk_total']);
  String get diskUsed => _formatBytes(system['disk_used']);
  String get uptime => system['uptime']?.toString() ?? '-';
  String get hostname => system['hostname']?.toString() ?? '-';
  String get os => system['os']?.toString() ?? '-';
  String get panelTitle => system['panel_title']?.toString() ?? '';

  // 仪表盘数据 — 字段名匹配后端实际返回
  int get totalTasks => (dashboard['task_count'] as num?)?.toInt() ?? 0;
  int get enabledTasks => (dashboard['enabled_tasks'] as num?)?.toInt() ?? 0;
  int get runningTasks => (dashboard['running_tasks'] as num?)?.toInt() ?? 0;
  int get disabledTasks => totalTasks - enabledTasks;
  int get todaySuccess => (dashboard['success_logs'] as num?)?.toInt() ?? 0;
  int get todayFailed => (dashboard['failed_logs'] as num?)?.toInt() ?? 0;
  List<dynamic> get recentLogs => dashboard['recent_logs'] as List? ?? [];
  List<dynamic> get executionTrend => dashboard['daily_stats'] as List? ?? [];

  DashboardData copyWith({
    Map<String, dynamic>? system,
    Map<String, dynamic>? dashboard,
    bool? loading,
    String? error,
  }) {
    return DashboardData(
      system: system ?? this.system,
      dashboard: dashboard ?? this.dashboard,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardData> {
  DashboardNotifier() : super(const DashboardData());

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final dio = DioClient.instance.dio;
      final results = await Future.wait([
        dio.get(ApiEndpoints.systemInfo),
        dio.get(ApiEndpoints.dashboard),
        dio.get(ApiEndpoints.panelSettings),
      ]);
      final sysData = extractData(results[0].data);
      final dashData = extractData(results[1].data);
      final panelData = extractData(results[2].data);
      final sysMap = sysData is Map<String, dynamic>
          ? Map<String, dynamic>.from(sysData)
          : <String, dynamic>{};
      if (panelData is Map) {
        final title = panelData['panel_title']?.toString() ?? '';
        if (title.isNotEmpty) {
          sysMap['panel_title'] = title;
        }
      }
      state = state.copyWith(
        system: sysMap,
        dashboard: dashData is Map<String, dynamic> ? dashData : {},
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '加载失败');
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardData>((ref) {
      return DashboardNotifier();
    });
