import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/task_stats.dart';

class TaskStatsBar extends StatelessWidget {
  final TaskStats stats;
  final VoidCallback? onTap;

  const TaskStatsBar({super.key, required this.stats, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = stats.contextUsagePercent;
    Color usageColor = Colors.green;
    if (usage > 75) {
      usageColor = Colors.red;
    } else if (usage > 45) {
      usageColor = Colors.amber;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // TPS / Speed Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: stats.isStreaming
                        ? Colors.blue.withValues(alpha: 0.2)
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: stats.isStreaming
                          ? Colors.blue.withValues(alpha: 0.5)
                          : theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.3,
                            ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.bolt,
                        size: 13,
                        color: stats.isStreaming
                            ? Colors.blue
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        stats.formattedTps,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: stats.isStreaming
                              ? Colors.blue
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Context Usage Details
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.gear,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          stats.formattedContextRatio,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Tool Calls & Duration
                if (stats.toolCallsCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🛠️ ${stats.toolCallsCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],

                if (stats.durationMs > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    stats.formattedDuration,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 4),

            // Mini Context Usage Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (usage / 100).clamp(0.01, 1.0),
                minHeight: 2.5,
                backgroundColor: theme.colorScheme.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation<Color>(usageColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
