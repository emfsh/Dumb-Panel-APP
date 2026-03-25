/// 从 API 响应中提取 data 字段
/// 后端格式：response.Success() 直接输出，某些接口用 gin.H{"data": ...} 包了一层
dynamic extractData(dynamic responseData) {
  if (responseData is Map<String, dynamic> &&
      responseData.containsKey('data')) {
    return responseData['data'];
  }
  return responseData;
}

/// 从分页响应中提取列表和总数
/// 后端 response.Paginated() 格式: {data: [...], total: N, page: N, page_size: N}
({List<Map<String, dynamic>> items, int total}) extractPaginated(
  dynamic responseData,
) {
  if (responseData is Map<String, dynamic>) {
    final dataField = responseData['data'];
    // {data: [...], total: N} — 标准分页格式
    if (dataField is List) {
      final items = dataField.whereType<Map<String, dynamic>>().toList();
      final total = _toInt(responseData['total']) ?? items.length;
      return (items: items, total: total);
    }
    // 兜底：{data: {data: [...], total: N}}
    if (dataField is Map<String, dynamic>) {
      final innerList = dataField['data'];
      if (innerList is List) {
        final items = innerList.whereType<Map<String, dynamic>>().toList();
        final total = _toInt(dataField['total']) ?? items.length;
        return (items: items, total: total);
      }
    }
  }
  // 直接是列表
  if (responseData is List) {
    final items = responseData.whereType<Map<String, dynamic>>().toList();
    return (items: items, total: items.length);
  }
  return (items: <Map<String, dynamic>>[], total: 0);
}

/// 安全转 int
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
