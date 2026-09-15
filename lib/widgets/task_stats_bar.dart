import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/task_stats.dart';
import 'package:workfromphone/theme/app_theme.dart';

class TaskStatsBar extends StatelessWidget {
  final TaskStats stats;
  final VoidCallback? onTap;

  const TaskStatsBar({super.key, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final usage = stats.contextUsagePercent;
    final usageTone = usage > 75
        ? AppTone.danger
        : usage > 45
        ? AppTone.warning
        : AppTone.primary;
    const metaStyle = TextStyle(fontSize: 12, color: AppColors.textSecondary);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.bolt_fill,
                    size: 12,
                    color: stats.isStreaming
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Text(
                    stats.formattedTps,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: stats.isStreaming
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      stats.formattedContextRatio,
                      style: metaStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stats.toolCallsCount > 0) ...[
                    const SizedBox(width: AppSpace.sm),
                    const Icon(
                      CupertinoIcons.hammer,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text('${stats.toolCallsCount}', style: metaStyle),
                  ],
                  if (stats.durationMs > 0) ...[
                    const SizedBox(width: AppSpace.md),
                    Text(stats.formattedDuration, style: metaStyle),
                  ],
                ],
              ),
            ),
            // Context window usage.
            LinearProgressIndicator(
              value: (usage / 100).clamp(0.01, 1.0),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(usageTone.foreground),
            ),
          ],
        ),
      ),
    );
  }
}
