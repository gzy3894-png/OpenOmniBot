import 'package:flutter/material.dart';
import 'package:ui/theme/theme_context.dart';

typedef CodexGoalSaveCallback = Future<bool> Function(String objective);

/// Independent editor for a thread Goal.
///
/// The controller belongs to this sheet and is disposed when the sheet closes,
/// so Goal editing can never reuse or overwrite the main chat composer draft.
class CodexGoalEditorSheet extends StatefulWidget {
  const CodexGoalEditorSheet({
    super.key,
    required this.initialGoal,
    required this.onSave,
  });

  final String initialGoal;
  final CodexGoalSaveCallback onSave;

  @override
  State<CodexGoalEditorSheet> createState() => _CodexGoalEditorSheetState();
}

class _CodexGoalEditorSheetState extends State<CodexGoalEditorSheet> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _errorText;

  bool get _isEnglish =>
      Localizations.localeOf(context).languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialGoal.trim());
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (_errorText == null || !mounted) {
      return;
    }
    setState(() {
      _errorText = null;
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final objective = _controller.text.trim();
    if (objective.isEmpty) {
      setState(() {
        _errorText = _isEnglish
            ? 'Enter a goal before saving.'
            : '请输入目标后再保存。';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    var saved = false;
    try {
      saved = await widget.onSave(objective);
    } catch (_) {
      saved = false;
    }
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _errorText = _isEnglish
          ? 'Goal was not saved. Check the error and try again.'
          : '目标未保存，请检查错误后重试。';
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final english = _isEnglish;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_saving,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: Material(
            color: palette.surfacePrimary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.borderSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    english ? 'Edit Goal' : '编辑目标',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    english
                        ? 'This updates the thread Goal. Normal chat messages stay in the main composer.'
                        : '这里只更新当前线程目标；普通消息仍在主输入框发送。',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('codex-goal-editor-field'),
                    controller: _controller,
                    autofocus: true,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: english
                          ? 'Describe the goal…'
                          : '描述目标…',
                      errorText: _errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('codex-goal-editor-cancel'),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(english ? 'Cancel' : '取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const ValueKey('codex-goal-editor-save'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(english ? 'Save and send' : '保存并发送'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
