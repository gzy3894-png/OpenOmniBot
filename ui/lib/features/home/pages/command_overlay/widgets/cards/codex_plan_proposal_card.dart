import 'package:flutter/material.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/theme/theme_context.dart';

/// Bridge so the plan proposal card can invoke ChatPage approve/reject without
/// plumbing callbacks through the entire message list.
class CodexPlanProposalBridge {
  static Future<void> Function({
    required String cardId,
    required bool approved,
    String? planText,
  })?
  handler;
}

/// Main-transcript plan proposal (B7): show structured plan + approve/reject.
class CodexPlanProposalCard extends StatefulWidget {
  const CodexPlanProposalCard({super.key, required this.cardData});

  final Map<String, dynamic> cardData;

  @override
  State<CodexPlanProposalCard> createState() => _CodexPlanProposalCardState();
}

class _CodexPlanProposalCardState extends State<CodexPlanProposalCard> {
  bool _isSubmitting = false;
  String? _localStatus;

  @override
  void didUpdateWidget(covariant CodexPlanProposalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = (oldWidget.cardData['cardId'] ?? '').toString();
    final nextId = (widget.cardData['cardId'] ?? '').toString();
    if (oldId != nextId) {
      _localStatus = null;
      _isSubmitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final isEnglish = LegacyTextLocalizer.isEnglish;
    final title = (widget.cardData['title'] ?? '').toString().trim().isEmpty
        ? (isEnglish ? 'Plan proposal' : '计划方案')
        : (widget.cardData['title'] ?? '').toString().trim();
    final planText = (widget.cardData['planText'] ?? '').toString().trim();
    final explanation = (widget.cardData['explanation'] ?? '')
        .toString()
        .trim();
    final cardStatus = (widget.cardData['status'] ?? 'pending')
        .toString()
        .trim()
        .toLowerCase();
    final status = _localStatus ?? cardStatus;
    final isPending = status == 'pending' || status == 'running';
    final canAct =
        isPending && !_isSubmitting && CodexPlanProposalBridge.handler != null;
    final steps = _resolveSteps(widget.cardData['planSteps']);

    return Container(
      key: const ValueKey('codex-plan-proposal-card-surface'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? palette.surfaceSecondary
            : const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.isDarkTheme
              ? palette.borderSubtle
              : const Color(0xFFE0E3E7),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
              _StatusChip(status: status, isEnglish: isEnglish),
            ],
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              explanation,
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final step in steps) ...[
              _PlanStepRow(step: step, palette: palette),
              const SizedBox(height: 6),
            ],
          ] else if (planText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              planText,
              style: TextStyle(
                fontSize: 12.5,
                color: palette.textPrimary,
                height: 1.45,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              isEnglish ? 'Waiting for plan content…' : '等待计划内容…',
              style: TextStyle(
                fontSize: 12,
                color: palette.textTertiary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (isPending) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canAct ? () => _submit(approved: false) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.textSecondary,
                      side: BorderSide(color: palette.borderSubtle),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      isEnglish ? 'Reject & keep planning' : '拒绝，继续规划',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: canAct ? () => _submit(approved: true) : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      isEnglish ? 'Approve & implement' : '批准并实施',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              _terminalHint(status: status, isEnglish: isEnglish),
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit({required bool approved}) async {
    final handler = CodexPlanProposalBridge.handler;
    if (handler == null || _isSubmitting) {
      return;
    }
    final cardId = (widget.cardData['cardId'] ?? widget.cardData['id'] ?? '')
        .toString()
        .trim();
    if (cardId.isEmpty) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _localStatus = approved ? 'approved' : 'rejected';
    });
    try {
      await handler(
        cardId: cardId,
        approved: approved,
        planText: (widget.cardData['planText'] ?? '').toString(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localStatus = 'pending';
        _isSubmitting = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });
  }

  static List<_PlanStepView> _resolveSteps(dynamic raw) {
    if (raw is! List) {
      return const <_PlanStepView>[];
    }
    final steps = <_PlanStepView>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final step = (map['step'] ?? map['text'] ?? map['title'] ?? '')
          .toString()
          .trim();
      if (step.isEmpty) continue;
      final status = (map['status'] ?? map['state'] ?? 'pending')
          .toString()
          .trim()
          .toLowerCase();
      steps.add(_PlanStepView(text: step, status: status));
    }
    return steps;
  }

  static String _terminalHint({
    required String status,
    required bool isEnglish,
  }) {
    switch (status) {
      case 'approved':
        return isEnglish
            ? 'Approved — implementing…'
            : '已批准，开始实施…';
      case 'rejected':
        return isEnglish
            ? 'Rejected — stay in plan mode'
            : '已拒绝，仍停留在计划模式';
      default:
        return isEnglish ? 'Plan decision recorded' : '计划决策已记录';
    }
  }
}

class _PlanStepView {
  const _PlanStepView({required this.text, required this.status});

  final String text;
  final String status;
}

class _PlanStepRow extends StatelessWidget {
  const _PlanStepRow({required this.step, required this.palette});

  final _PlanStepView step;
  final OmniThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _statusVisual(step.status);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            step.text,
            style: TextStyle(
              fontSize: 12.5,
              color: palette.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  (IconData, Color) _statusVisual(String status) {
    final normalized = status.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized == 'completed' ||
        normalized == 'complete' ||
        normalized == 'done') {
      return (Icons.check_circle_outline, const Color(0xFF2F9D62));
    }
    if (normalized == 'inprogress' ||
        normalized == 'running' ||
        normalized == 'active') {
      return (Icons.timelapse, palette.accentPrimary);
    }
    return (Icons.radio_button_unchecked, palette.textTertiary);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isEnglish});

  final String status;
  final bool isEnglish;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final label = switch (status) {
      'approved' => isEnglish ? 'Approved' : '已批准',
      'rejected' => isEnglish ? 'Rejected' : '已拒绝',
      'running' => isEnglish ? 'Drafting' : '规划中',
      _ => isEnglish ? 'Awaiting approval' : '待审批',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}
