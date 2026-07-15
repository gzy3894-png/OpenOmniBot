import 'package:flutter/material.dart';
import 'package:ui/theme/theme_context.dart';

/// Codex 目标模式常显条：展示当前目标正文，可选清除。
///
/// 纯 UI，不调用 RPC。由 ChatPage / M6 挂载到输入区上方，
/// 状态与清除回调由外层（M4）维护。
class CodexGoalModeBar extends StatelessWidget {
  const CodexGoalModeBar({
    super.key,
    this.goalText,
    this.onClear,
    this.prefixLabel,
    this.showWhenEmpty = false,
    this.emptyPlaceholder,
    this.compact = false,
  });

  /// 当前目标正文；空白时按 [showWhenEmpty] 决定是否展示。
  final String? goalText;

  /// 清除按钮回调；为 null 时不显示清除按钮。
  final VoidCallback? onClear;

  /// 前缀标签；null 时按语言默认「目标:」/ `Goal:`。
  final String? prefixLabel;

  /// 目标为空时是否仍显示占位条。
  final bool showWhenEmpty;

  /// 空态占位文案；null 时按语言默认。
  final String? emptyPlaceholder;

  /// 更紧凑的内边距（嵌在窄栏时用）。
  final bool compact;

  static String defaultPrefixLabel(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return english ? 'Goal:' : '目标:';
  }

  static String defaultEmptyPlaceholder(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return english ? 'No goal set' : '尚未设置目标';
  }

  String get _trimmedGoal => (goalText ?? '').trim();

  bool get _hasGoal => _trimmedGoal.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasGoal && !showWhenEmpty) {
      return const SizedBox.shrink();
    }

    final palette = context.omniPalette;
    final english = Localizations.localeOf(context).languageCode == 'en';
    final label = (prefixLabel ?? '').trim().isEmpty
        ? defaultPrefixLabel(context)
        : prefixLabel!.trim();
    final bodyText = _hasGoal
        ? _trimmedGoal
        : (emptyPlaceholder ?? defaultEmptyPlaceholder(context));
    final surface = context.isDarkTheme
        ? palette.surfaceSecondary.withValues(alpha: 0.88)
        : const Color(0xFFF4F7FD);
    final borderColor = context.isDarkTheme
        ? palette.borderSubtle
        : const Color(0x14000000);
    final labelColor = context.isDarkTheme
        ? palette.accentPrimary
        : const Color(0xFF3D6FDB);
    final bodyColor = _hasGoal
        ? (context.isDarkTheme
              ? palette.textPrimary
              : const Color(0xFF2F3A4D))
        : (context.isDarkTheme
              ? palette.textTertiary
              : const Color(0xFF7A879C));
    final clearColor = context.isDarkTheme
        ? palette.textSecondary
        : const Color(0xFF54627A);
    final horizontal = compact ? 10.0 : 12.0;
    final vertical = compact ? 6.0 : 8.0;

    return Semantics(
      container: true,
      label: english
          ? (_hasGoal ? 'Active goal: $_trimmedGoal' : 'Goal mode, no goal set')
          : (_hasGoal ? '当前目标：$_trimmedGoal' : '目标模式，尚未设置目标'),
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const ValueKey('codex-goal-mode-bar'),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            horizontal,
            vertical,
            onClear == null ? horizontal : horizontal - 2,
            vertical,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.flag_rounded,
                  size: compact ? 14 : 15,
                  color: labelColor,
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: RichText(
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$label ',
                        style: TextStyle(
                          fontSize: compact ? 12 : 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                          letterSpacing: 0.1,
                        ),
                      ),
                      TextSpan(
                        text: bodyText,
                        style: TextStyle(
                          fontSize: compact ? 12 : 12.5,
                          height: 1.35,
                          fontWeight: _hasGoal
                              ? FontWeight.w500
                              : FontWeight.w400,
                          color: bodyColor,
                          fontStyle: _hasGoal
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: english ? 'Clear goal' : '清除目标',
                  waitDuration: const Duration(milliseconds: 350),
                  child: InkWell(
                    key: const ValueKey('codex-goal-mode-bar-clear'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: onClear,
                    child: Container(
                      width: compact ? 22 : 24,
                      height: compact ? 22 : 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: clearColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: compact ? 13 : 14,
                        color: clearColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
