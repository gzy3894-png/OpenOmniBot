import 'package:flutter/material.dart';
import 'package:ui/theme/theme_context.dart';

/// Codex 上下文顶栏：展示阈值（及可选用量），点击由父级打开调值 sheet。
///
/// 纯 UI，不读写 conf / 不调 RPC。由 ChatPage 挂到输入柱 [topBanner]
///（可与 [CodexGoalModeBar] 叠放）。高度变化通过 [onHeightChanged] 上报。
class CodexContextBar extends StatelessWidget {
  const CodexContextBar({
    super.key,
    this.threshold = 128000,
    this.usedTokens,
    this.usageRatio,
    this.autoCompactionEnabled,
    this.onTap,
    this.compact = false,
    this.visible = true,
    this.onHeightChanged,
  });

  /// 上下文 token 阈值（conf 或默认 128000）。
  final int threshold;

  /// 可选已用 token；null 时不展示用量数字。
  final int? usedTokens;

  /// 可选用量比例 0..1；与 [usedTokens] 并存时优先展示 used/threshold。
  final double? usageRatio;

  /// 自动压缩开关状态；null 不展示芯片，非 null 展示「自动压缩 开/关」。
  final bool? autoCompactionEnabled;

  /// 整条点击；通常打开阈值 sheet。null 时不可点。
  final VoidCallback? onTap;

  /// 更紧凑的内边距（嵌在窄栏时用）。
  final bool compact;

  /// 是否可见；false 时高度 0 且触发 [onHeightChanged](0)。
  final bool visible;

  /// bar 实测高度变化回调（隐藏时为 0）。
  final ValueChanged<double>? onHeightChanged;

  static String humanizeTokens(int tokens) {
    final n = tokens < 0 ? 0 : tokens;
    if (n >= 1000000) {
      final m = n / 1000000;
      final text = m == m.roundToDouble()
          ? m.toInt().toString()
          : m.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      return '${text}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      final text = k == k.roundToDouble()
          ? k.toInt().toString()
          : k.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      return '${text}k';
    }
    return n.toString();
  }

  static String defaultPrefixLabel(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    return english ? 'Context' : '上下文';
  }

  int get _safeThreshold => threshold > 0 ? threshold : 128000;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return _CodexContextBarHeightReporter(
        onHeightChanged: onHeightChanged,
        child: const SizedBox.shrink(),
      );
    }

    final palette = context.omniPalette;
    final english = Localizations.localeOf(context).languageCode == 'en';
    final label = defaultPrefixLabel(context);
    final thresholdText = humanizeTokens(_safeThreshold);

    String? usageText;
    final used = usedTokens;
    if (used != null && used >= 0) {
      usageText = '${humanizeTokens(used)} / $thresholdText';
    } else if (usageRatio != null) {
      final ratio = usageRatio!.clamp(0.0, 1.0);
      final pct = (ratio * 100).round();
      usageText = english ? '$pct% of $thresholdText' : '$pct% · $thresholdText';
    }

    final bodyPrimary = usageText ?? thresholdText;

    final surface = context.isDarkTheme
        ? palette.surfaceSecondary.withValues(alpha: 0.88)
        : const Color(0xFFF4F7FD).withValues(alpha: 0.92);
    final borderColor = context.isDarkTheme
        ? palette.borderSubtle
        : const Color(0x14000000);
    final labelColor = context.isDarkTheme
        ? palette.accentPrimary
        : const Color(0xFF3D6FDB);
    final bodyColor = context.isDarkTheme
        ? palette.textPrimary
        : const Color(0xFF2F3A4D);
    final chipBg = context.isDarkTheme
        ? palette.surfacePrimary.withValues(alpha: 0.55)
        : const Color(0x14000000);
    final chipFg = context.isDarkTheme
        ? palette.textSecondary
        : const Color(0xFF54627A);
    final horizontal = compact ? 10.0 : 12.0;
    final vertical = compact ? 6.0 : 7.0;
    final iconSize = compact ? 14.0 : 15.0;
    final fontSize = compact ? 12.0 : 12.5;

    final compactOn = autoCompactionEnabled;
    final compactChipLabel = compactOn == null
        ? null
        : (english
              ? (compactOn ? 'Auto-compact on' : 'Auto-compact off')
              : (compactOn ? '自动压缩 开' : '自动压缩 关'));

    final semanticsLabel = english
        ? (usageText != null
              ? 'Context $usageText'
              : 'Context threshold $thresholdText')
        : (usageText != null
              ? '上下文 $usageText'
              : '上下文阈值 $thresholdText');

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.data_usage_rounded,
          size: iconSize,
          color: labelColor,
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.1,
                  ),
                ),
                TextSpan(
                  text: bodyPrimary,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: bodyColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (compactChipLabel != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 7,
              vertical: compact ? 2 : 3,
            ),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              compactChipLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: chipFg,
              ),
            ),
          ),
        ],
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: compact ? 16 : 18,
            color: chipFg,
          ),
        ],
      ],
    );

    final bar = Container(
      key: const ValueKey('codex-context-bar'),
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: compact ? 36 : 40,
        maxHeight: compact ? 40 : 44,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: horizontal,
        vertical: vertical,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.centerLeft,
      child: content,
    );

    return _CodexContextBarHeightReporter(
      onHeightChanged: onHeightChanged,
      child: Semantics(
        container: true,
        button: onTap != null,
        label: semanticsLabel,
        child: Material(
          color: Colors.transparent,
          child: onTap == null
              ? bar
              : InkWell(
                  key: const ValueKey('codex-context-bar-tap'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  child: bar,
                ),
        ),
      ),
    );
  }
}

/// 测量 [child] 高度并在变化时回调；隐藏态 child 为 shrink 时上报 0。
class _CodexContextBarHeightReporter extends StatefulWidget {
  const _CodexContextBarHeightReporter({
    required this.child,
    this.onHeightChanged,
  });

  final Widget child;
  final ValueChanged<double>? onHeightChanged;

  @override
  State<_CodexContextBarHeightReporter> createState() =>
      _CodexContextBarHeightReporterState();
}

class _CodexContextBarHeightReporterState
    extends State<_CodexContextBarHeightReporter> {
  double _lastReported = -1;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(covariant _CodexContextBarHeightReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  void _scheduleReport() {
    if (widget.onHeightChanged == null) return;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      final height = (box is RenderBox && box.hasSize)
          ? box.size.height
          : 0.0;
      final normalized = height.isFinite ? height : 0.0;
      if ((normalized - _lastReported).abs() < 0.5) return;
      _lastReported = normalized;
      widget.onHeightChanged?.call(normalized);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _scheduleReport();
        return false;
      },
      child: SizeChangedLayoutNotifier(child: widget.child),
    );
  }
}
