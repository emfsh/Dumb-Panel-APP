import 'package:flutter/material.dart';

class TaskStatsCard extends StatelessWidget {
  final int total;
  final int enabled;
  final int running;
  final int disabled;
  final int todaySuccess;
  final int todayFailed;

  const TaskStatsCard({
    super.key,
    required this.total,
    required this.enabled,
    required this.running,
    required this.disabled,
    required this.todaySuccess,
    required this.todayFailed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('任务概览', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatItem(
                  label: '总任务',
                  value: '$total',
                  color: theme.colorScheme.primary,
                ),
                _StatItem(label: '已启用', value: '$enabled', color: Colors.green),
                _StatItem(label: '运行中', value: '$running', color: Colors.blue),
                _StatItem(label: '已禁用', value: '$disabled', color: Colors.grey),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                _StatItem(
                  label: '今日成功',
                  value: '$todaySuccess',
                  color: Colors.green,
                ),
                _StatItem(
                  label: '今日失败',
                  value: '$todayFailed',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
