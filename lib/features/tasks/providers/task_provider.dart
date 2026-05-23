import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/models/task.dart';
import '../../../shared/models/task_log.dart';
import '../../../shared/utils/api_utils.dart';

const _unset = Object();

class TaskListState {
  final List<Task> tasks;
  final int total;
  final bool loading;
  final String? error;
  final String keyword;
  final String? statusFilter;
  final String? labelFilter;

  const TaskListState({
    this.tasks = const [],
    this.total = 0,
    this.loading = false,
    this.error,
    this.keyword = '',
    this.statusFilter,
    this.labelFilter,
  });

  TaskListState copyWith({
    List<Task>? tasks,
    int? total,
    bool? loading,
    String? error,
    String? keyword,
    Object? statusFilter = _unset,
    Object? labelFilter = _unset,
  }) {
    return TaskListState(
      tasks: tasks ?? this.tasks,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      error: error,
      keyword: keyword ?? this.keyword,
      statusFilter: identical(statusFilter, _unset)
          ? this.statusFilter
          : statusFilter as String?,
      labelFilter: identical(labelFilter, _unset)
          ? this.labelFilter
          : labelFilter as String?,
    );
  }
}

class TaskNotifier extends StateNotifier<TaskListState> {
  TaskNotifier() : super(const TaskListState());

  Future<void> load({bool refresh = false}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final dio = DioClient.instance.dio;
      final queryParams = <String, dynamic>{
        'all': 1,
      };
      if (state.keyword.isNotEmpty) {
        queryParams['keyword'] = state.keyword;
      }
      if (state.statusFilter != null) {
        queryParams['status'] = state.statusFilter;
      }
      if (state.labelFilter != null) {
        queryParams['label'] = state.labelFilter;
      }

      final response = await dio.get(
        ApiEndpoints.tasks,
        queryParameters: queryParams,
      );
      final paginated = extractPaginated(response.data);
      final items = paginated.items.map((e) => Task.fromJson(e)).toList();
      final total = paginated.total;

      state = state.copyWith(
        tasks: items,
        total: total,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '加载失败');
    }
  }

  Future<void> loadMore() async {
    return;
  }

  void setKeyword(String keyword) {
    state = state.copyWith(keyword: keyword);
    load(refresh: true);
  }

  void setStatusFilter(String? status) {
    state = state.copyWith(statusFilter: status);
    load(refresh: true);
  }

  void setLabelFilter(String? label) {
    state = state.copyWith(labelFilter: label);
    load(refresh: true);
  }

  Future<void> runTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskRun(id));
    await load(refresh: true);
  }

  Future<void> stopTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskStop(id));
    await load(refresh: true);
  }

  Future<void> enableTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskEnable(id));
    await load(refresh: true);
  }

  Future<void> disableTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskDisable(id));
    await load(refresh: true);
  }

  Future<void> deleteTask(int id) async {
    await DioClient.instance.dio.delete(ApiEndpoints.taskById(id));
    await load(refresh: true);
  }

  Future<TaskLog?> fetchLatestLog(int id) async {
    try {
      final response = await DioClient.instance.dio.get(
        ApiEndpoints.taskLatestLog(id),
      );
      final data = extractData(response.data);
      if (data is Map) {
        return TaskLog.fromJson(Map<String, dynamic>.from(data));
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> pinTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskPin(id));
    await load(refresh: true);
  }

  Future<void> unpinTask(int id) async {
    await DioClient.instance.dio.put(ApiEndpoints.taskUnpin(id));
    await load(refresh: true);
  }

  Future<void> copyTask(int id) async {
    await DioClient.instance.dio.post(ApiEndpoints.taskCopy(id));
    await load(refresh: true);
  }
}

final taskProvider = StateNotifierProvider<TaskNotifier, TaskListState>((ref) {
  return TaskNotifier();
});
