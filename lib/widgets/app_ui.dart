import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/theme/app_theme.dart';

/// Uppercase section label that sits above a group, e.g. "RECENT  4".
class SectionLabel extends StatelessWidget {
  final String text;
  final int? count;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionLabel(
    this.text, {
    super.key,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 0, 2, AppSpace.sm),
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Text(text.toUpperCase(), style: style),
            if (count != null) ...[
              const SizedBox(width: AppSpace.sm),
              Text(
                '$count',
                style: style?.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  final AppTone tone;
  final double size;

  const StatusDot({super.key, required this.tone, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.foreground, shape: BoxShape.circle),
    );
  }
}

/// Dot + label status indicator, e.g. "● Online".
class StatusPill extends StatelessWidget {
  final String label;
  final AppTone tone;
  final bool busy;

  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: tone.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: tone.foreground,
              ),
            )
          else
            StatusDot(tone: tone, size: 6),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tone.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact uppercase badge, e.g. "ACTIVE", "FREE", "FLUTTER".
class ToneBadge extends StatelessWidget {
  final String label;
  final AppTone tone;
  final IconData? icon;

  const ToneBadge({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: tone.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone.foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 10,
              height: 1.4,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: tone.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Square icon tile used as a leading visual in rows and headers.
class IconTile extends StatelessWidget {
  final IconData icon;
  final AppTone tone;
  final double size;

  const IconTile({
    super.key,
    required this.icon,
    this.tone = AppTone.neutral,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: tone.outline),
      ),
      child: Icon(icon, size: size * 0.5, color: tone.foreground),
    );
  }
}

/// Centered empty / error state: icon, title, message and optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppTone tone;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = AppTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon: icon, tone: tone, size: 48),
          const SizedBox(height: AppSpace.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
        ],
      ),
    );
  }
}

/// Title row for bottom sheets: title, optional subtitle and trailing actions.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.sm,
        AppSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Small icon-only action (min 32x32 target) with a required tooltip.
class CompactIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const CompactIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      color: color ?? AppColors.textMuted,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onPressed,
    );
  }
}

/// Full-width tappable suggestion row used in chat empty states.
class PromptSuggestion extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const PromptSuggestion({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 13)),
                ),
                const Icon(
                  CupertinoIcons.arrow_right,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared layout for a chat message: user turns sit in a raised panel,
/// assistant turns render flat on the page so long answers stay readable.
class MessageShell extends StatelessWidget {
  final bool isUser;
  final Widget leading;
  final String label;
  final List<Widget> actions;
  final List<Widget> children;

  const MessageShell({
    super.key,
    required this.isUser,
    required this.leading,
    required this.label,
    required this.actions,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        leading,
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        ...actions,
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 32, child: header),
        const SizedBox(height: AppSpace.xs),
        ...children,
      ],
    );

    if (!isUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.sm,
          AppSpace.sm,
        ),
        child: body,
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.xs,
        AppSpace.xs,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: body,
    );
  }
}

/// Bordered composer frame whose outline turns primary while focused.
class ComposerFrame extends StatelessWidget {
  final FocusNode focusNode;
  final Widget child;

  const ComposerFrame({
    super.key,
    required this.focusNode,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: focusNode.hasFocus ? AppColors.primary : AppColors.border,
            width: focusNode.hasFocus ? 1.5 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Input decoration for a text field that lives inside a [ComposerFrame].
const composerInputDecoration = InputDecoration(
  isDense: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  contentPadding: EdgeInsets.fromLTRB(
    AppSpace.md,
    AppSpace.md,
    AppSpace.md,
    AppSpace.xs,
  ),
);

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppTone tone = AppTone.neutral,
  Duration duration = const Duration(seconds: 3),
}) {
  final icon = switch (tone) {
    AppTone.danger => CupertinoIcons.exclamationmark_circle,
    AppTone.warning => CupertinoIcons.exclamationmark_triangle,
    AppTone.success => CupertinoIcons.check_mark_circled,
    _ => null,
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: duration,
      shape: tone == AppTone.neutral
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: BorderSide(color: tone.outline),
            ),
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: tone.foreground),
            const SizedBox(width: AppSpace.sm),
          ],
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
