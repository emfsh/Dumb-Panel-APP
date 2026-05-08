import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class TaskCronList extends StatelessWidget {
  final List<String> expressions;
  final bool compact;
  final bool numbered;

  const TaskCronList({
    super.key,
    required this.expressions,
    this.compact = false,
    this.numbered = true,
  });

  List<String> get _normalized =>
      expressions.map((item) => item.trim()).where((item) => item.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final items = _normalized;

    if (items.isEmpty) {
      return Text(
        '-',
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final isMulti = items.length > 1;
    final codeBg = isLight ? AppColors.slate50 : AppColors.slate800;
    final codeBorder = isLight ? AppColors.slate200 : AppColors.slate700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 4 : 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (numbered && isMulti)
                Container(
                  width: compact ? 18 : 20,
                  height: compact ? 18 : 20,
                  margin: EdgeInsets.only(top: compact ? 2 : 1, right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(isLight ? 24 : 38),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: compact ? 5 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: codeBg,
                    borderRadius: BorderRadius.circular(compact ? 8 : 10),
                    border: Border.all(color: codeBorder),
                  ),
                  child: SelectableText(
                    items[i],
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      height: compact ? 1.35 : 1.45,
                      fontFamily: 'monospace',
                      color: isLight ? AppColors.slate700 : AppColors.slate200,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
