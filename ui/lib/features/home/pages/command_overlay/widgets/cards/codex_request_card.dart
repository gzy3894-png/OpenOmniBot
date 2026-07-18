import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/conversation_history_service.dart';
import 'package:ui/services/debug_file_log.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/theme_context.dart';

class CodexRequestCard extends StatefulWidget {
  const CodexRequestCard({super.key, required this.cardData});

  final Map<String, dynamic> cardData;

  @override
  State<CodexRequestCard> createState() => _CodexRequestCardState();
}

class _CodexRequestCardState extends State<CodexRequestCard>
    with WidgetsBindingObserver {
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _answerFocusNode = FocusNode(
    debugLabel: 'codex_request_answer',
  );
  final GlobalKey _answerInputKey = GlobalKey(
    debugLabel: 'codex_request_answer_input',
  );
  Timer? _ensureAnswerInputTimer;
  Timer? _lateEnsureAnswerInputTimer;
  bool _isSubmitting = false;
  String? _localStatus;
  List<String> _localAnswers = const <String>[];
  String? _localSubmittedAction;
  String? _submitErrorMessage;
  String? _selectedOptionValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _answerFocusNode.addListener(_handleAnswerFocusChanged);
    _syncDefaultSelection();
    _hydratePersistedResponse();
  }

  @override
  void didUpdateWidget(covariant CodexRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_requestRenderSignature(oldWidget.cardData) !=
        _requestRenderSignature(widget.cardData)) {
      _isSubmitting = false;
      _localStatus = null;
      _localAnswers = const <String>[];
      _localSubmittedAction = null;
      _submitErrorMessage = null;
      _selectedOptionValue = null;
      _answerController.clear();
      _syncDefaultSelection();
      _hydratePersistedResponse();
      if (_hasTerminalRequestStatus(widget.cardData)) {
        unawaited(
          _persistTerminalSnapshot(
            Map<String, dynamic>.from(widget.cardData),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ensureAnswerInputTimer?.cancel();
    _lateEnsureAnswerInputTimer?.cancel();
    _answerFocusNode
      ..removeListener(_handleAnswerFocusChanged)
      ..dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleEnsureAnswerInputVisible();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final kind = (widget.cardData['requestKind'] ?? '').toString();
    final title = (widget.cardData['title'] ?? 'Codex request').toString();
    final detail = _requestVisibleDetail(
      title,
      (widget.cardData['detail'] ?? '').toString(),
    );
    final rawCardStatus = _cardStatus(widget.cardData);
    final cardStatus =
        rawCardStatus == 'pending' &&
            !_hasCompleteServerRequestIdentity(widget.cardData)
        ? 'invalidated'
        : rawCardStatus;
    final status = cardStatus == 'pending'
        ? (_localStatus ?? 'pending')
        : cardStatus;
    final isPending = status == 'pending' && !_isSubmitting;
    final options = _resolveRequestOptions(widget.cardData);
    final hasOptions = options.isNotEmpty;
    final answers = _localAnswers.isNotEmpty
        ? _localAnswers
        : _stringList(widget.cardData['submittedAnswers']);
    final submittedAction =
        _localSubmittedAction ??
        _firstText([widget.cardData['submittedAction']]);
    final canSubmit =
        isPending &&
        (!hasOptions ||
            _selectedOptionValue != null ||
            _answerController.text.trim().isNotEmpty);

    return Container(
      key: const ValueKey('codex-request-card-surface'),
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
          Text(
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
          if (detail.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (kind == 'user_input' && status == 'pending') ...[
            if (hasOptions) ...[
              for (var index = 0; index < options.length; index++) ...[
                _RequestOptionTile(
                  index: index + 1,
                  option: options[index],
                  selected: options[index].value == _selectedOptionValue,
                  enabled: isPending,
                  onTap: () {
                    setState(() {
                      _selectedOptionValue = options[index].value;
                      _answerController.clear();
                    });
                  },
                ),
                const SizedBox(height: 4),
              ],
              _CustomAnswerInput(
                inputKey: _answerInputKey,
                controller: _answerController,
                focusNode: _answerFocusNode,
                enabled: isPending,
                onTap: () {
                  setState(() {
                    _selectedOptionValue = null;
                  });
                  _scheduleEnsureAnswerInputVisible();
                },
                onChanged: (value) {
                  setState(() {
                    if (value.trim().isNotEmpty) {
                      _selectedOptionValue = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
            ] else ...[
              TextField(
                controller: _answerController,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(fontSize: 12, color: palette.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Answer',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_submitErrorMessage != null && status == 'pending') ...[
            Text(
              _submitErrorMessage!,
              key: const ValueKey('codex-request-submit-error'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _RequestFooter(
            kind: kind,
            status: status,
            answers: answers,
            submittedAction: submittedAction,
            isPending: isPending,
            isSubmitting: _isSubmitting,
            canSubmit: canSubmit,
            onAccept: () => _respondApproval(true),
            onDecline: () => _respondApproval(false),
            onIgnore: _ignoreUserInput,
            onSubmit: _respondUserInput,
          ),
        ],
      ),
    );
  }

  Future<void> _respondApproval(bool accepted) async {
    final decision = accepted ? 'accepted' : 'declined';
    CodexApprovalRequestPayload request;
    try {
      request = CodexApprovalRequestPayload.fromCardData(widget.cardData);
    } catch (_) {
      await _markRequestInvalidated();
      return;
    }
    final threadId = (widget.cardData['threadId'] ?? '').toString().trim();
    final requestIdText = request.requestId.toString();
    final submitError = await _submit(
      () => CodexAppServerService.respondToApproval(
        request: request,
        accepted: accepted,
      ),
      decision,
    );
    // _submit swallows RPC errors after updating UI; log ring outcome here.
    final ok = submitError == null;
    unawaited(
      DebugFileLog.logApproval(
        'decision',
        requestId: requestIdText,
        decision: decision,
        threadId: threadId.isEmpty ? null : threadId,
        approvalKind: request.kind.name,
        serverRequestMethod: request.serverRequestMethod,
        sessionGeneration: request.sessionGeneration,
        success: ok,
        error: submitError,
      ),
    );
  }

  Future<void> _ignoreUserInput() async {
    final requestId = widget.cardData['requestId'];
    final sessionGeneration = _requestSessionGeneration(widget.cardData);
    final serverRequestMethod = _requestServerMethod(widget.cardData);
    if (requestId == null ||
        sessionGeneration == null ||
        serverRequestMethod == null) {
      await _markRequestInvalidated();
      return;
    }
    await _submit(() {
      return CodexAppServerService.ignoreUserInput(
        requestId: requestId,
        sessionGeneration: sessionGeneration,
        serverRequestMethod: serverRequestMethod,
      );
    }, 'ignored');
  }

  Future<void> _respondUserInput() async {
    final requestId = widget.cardData['requestId'];
    final sessionGeneration = _requestSessionGeneration(widget.cardData);
    final serverRequestMethod = _requestServerMethod(widget.cardData);
    final questionId = (widget.cardData['questionId'] ?? 'answer').toString();
    if (requestId == null ||
        sessionGeneration == null ||
        serverRequestMethod == null) {
      await _markRequestInvalidated();
      return;
    }
    final customAnswer = _answerController.text.trim();
    final answer = customAnswer.isNotEmpty
        ? customAnswer
        : (_selectedOptionValue ?? '').trim();
    if (answer.isEmpty) return;
    await _submit(
      () {
        return CodexAppServerService.respondToUserInput(
          requestId: requestId,
          sessionGeneration: sessionGeneration,
          serverRequestMethod: serverRequestMethod,
          questionId: questionId,
          answers: <String>[answer],
        );
      },
      'submitted',
      answers: <String>[answer],
    );
  }

  Future<Object?> _submit(
    Future<Map<String, dynamic>> Function() action,
    String submittedAction, {
    List<String> answers = const <String>[],
  }) async {
    if (_isSubmitting ||
        !_hasPendingEffectiveStatus ||
        !_hasCompleteServerRequestIdentity(widget.cardData)) {
      return StateError(
        'Codex server request is no longer pending.',
      );
    }
    final requestIdentity = _requestStorageIdentity(widget.cardData);
    setState(() {
      _isSubmitting = true;
      _submitErrorMessage = null;
    });
    try {
      final result = await action();
      if (!mounted) return null;
      if (result['ok'] == false) {
        throw StateError(
          (result['error'] ?? 'Server request response was rejected')
              .toString(),
        );
      }
      if (!_hasRequestIdentity(requestIdentity)) {
        return null;
      }
      if (_hasTerminalRequestStatus(widget.cardData)) {
        _finishSubmissionWithoutLocalOverride();
        return null;
      }
      final persisted = await _persistResponseStatus(
        'response_sent',
        answers,
        submittedAction: submittedAction,
        actionResult:
            _firstText([result['actionResult']]) ?? 'response_sent',
        resolved: false,
        expectedIdentity: requestIdentity,
      );
      if (!mounted) return null;
      if (!persisted ||
          !_hasRequestIdentity(requestIdentity) ||
          _hasTerminalRequestStatus(widget.cardData)) {
        if (_hasRequestIdentity(requestIdentity)) {
          _finishSubmissionWithoutLocalOverride();
        }
        return null;
      }
      setState(() {
        _localStatus = 'response_sent';
        _localAnswers = answers;
        _localSubmittedAction = submittedAction;
        _submitErrorMessage = null;
        _isSubmitting = false;
      });
      return null;
    } catch (error) {
      if (!mounted) return error;
      final failure = _serverRequestFailureDisposition(error);
      if (failure == _ServerRequestFailureDisposition.invalidated) {
        if (_hasRequestIdentity(requestIdentity)) {
          await _markRequestInvalidated(expectedIdentity: requestIdentity);
        }
        return error;
      }
      if (failure == _ServerRequestFailureDisposition.handledElsewhere) {
        if (!_hasRequestIdentity(requestIdentity)) {
          return error;
        }
        if (_hasTerminalRequestStatus(widget.cardData)) {
          _finishSubmissionWithoutLocalOverride();
          return error;
        }
        final persisted = await _persistResponseStatus(
          'response_sent',
          const <String>[],
          submittedAction: 'handled_elsewhere',
          actionResult: 'already_responded',
          resolved: false,
          expectedIdentity: requestIdentity,
        );
        if (!mounted) {
          return error;
        }
        if (!persisted ||
            !_hasRequestIdentity(requestIdentity) ||
            _hasTerminalRequestStatus(widget.cardData)) {
          if (_hasRequestIdentity(requestIdentity)) {
            _finishSubmissionWithoutLocalOverride();
          }
          return error;
        }
        setState(() {
          _localStatus = 'response_sent';
          _localAnswers = const <String>[];
          _localSubmittedAction = 'handled_elsewhere';
          _submitErrorMessage = null;
          _isSubmitting = false;
        });
        return error;
      }
      if (!mounted) return error;
      if (!_hasRequestIdentity(requestIdentity)) {
        return error;
      }
      if (_hasTerminalRequestStatus(widget.cardData)) {
        _finishSubmissionWithoutLocalOverride();
        return error;
      }
      setState(() {
        _localStatus = null;
        _submitErrorMessage = _requestSubmitErrorText(error);
        _isSubmitting = false;
      });
      return error;
    }
  }

  bool get _hasPendingEffectiveStatus =>
      _cardStatus(widget.cardData) == 'pending' &&
      (_localStatus == null || _localStatus == 'pending');

  Future<void> _markRequestInvalidated({String? expectedIdentity}) async {
    final requestIdentity =
        expectedIdentity ?? _requestStorageIdentity(widget.cardData);
    if (!_hasRequestIdentity(requestIdentity)) {
      return;
    }
    final persisted = await _persistResponseStatus(
      'invalidated',
      const <String>[],
      actionResult: 'invalidated',
      resolved: false,
      expectedIdentity: requestIdentity,
    );
    if (!mounted) {
      return;
    }
    if (!persisted) {
      _finishSubmissionWithoutLocalOverride();
      return;
    }
    setState(() {
      _localStatus = 'invalidated';
      _localAnswers = const <String>[];
      _localSubmittedAction = null;
      _submitErrorMessage = null;
      _isSubmitting = false;
    });
  }

  bool _hasRequestIdentity(String expectedIdentity) {
    return _requestStorageIdentity(widget.cardData) == expectedIdentity;
  }

  void _finishSubmissionWithoutLocalOverride() {
    if (!mounted) {
      return;
    }
    setState(() {
      _localStatus = null;
      _localAnswers = const <String>[];
      _localSubmittedAction = null;
      _submitErrorMessage = null;
      _isSubmitting = false;
    });
  }

  void _handleAnswerFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scheduleEnsureAnswerInputVisible();
  }

  void _scheduleEnsureAnswerInputVisible() {
    if (!_answerFocusNode.hasFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAnswerInputVisible();
    });
    _ensureAnswerInputTimer?.cancel();
    _lateEnsureAnswerInputTimer?.cancel();
    _ensureAnswerInputTimer = Timer(const Duration(milliseconds: 260), () {
      _ensureAnswerInputVisible();
    });
    _lateEnsureAnswerInputTimer = Timer(const Duration(milliseconds: 560), () {
      _ensureAnswerInputVisible();
    });
  }

  void _ensureAnswerInputVisible() {
    if (!mounted || !_answerFocusNode.hasFocus) {
      return;
    }
    final inputContext = _answerInputKey.currentContext;
    if (inputContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      inputContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.72,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  void _hydratePersistedResponse() {
    try {
      final raw = StorageService.getString(_requestStorageKey(widget.cardData));
      if (raw == null || raw.trim().isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      final status = decoded['status']?.toString().trim().toLowerCase();
      if (status == null || status.isEmpty) {
        return;
      }
      if (!_isRestorableRequestStatus(status)) {
        return;
      }
      final currentIdentity = _requestStorageIdentity(widget.cardData);
      final cachedIdentity = decoded['identity']?.toString().trim();
      if (cachedIdentity != null &&
          cachedIdentity.isNotEmpty &&
          cachedIdentity != currentIdentity) {
        return;
      }
      if (_cardStatus(widget.cardData) == 'pending' &&
          cachedIdentity != currentIdentity) {
        return;
      }
      if (_cardStatus(widget.cardData) == 'pending' &&
          _hasCompleteServerRequestIdentity(widget.cardData) &&
          status != 'response_sent' &&
          !_isTerminalRequestStatus(status)) {
        return;
      }
      _localStatus = status;
      _localAnswers = _stringList(decoded['answers']);
      _localSubmittedAction = _firstText([decoded['submittedAction']]);
    } catch (_) {
      return;
    }
  }

  void _syncDefaultSelection() {
    if (_cardStatus(widget.cardData) != 'pending' ||
        !_hasCompleteServerRequestIdentity(widget.cardData)) {
      return;
    }
    final options = _resolveRequestOptions(widget.cardData);
    if (options.isEmpty || _selectedOptionValue != null) {
      return;
    }
    if (_answerController.text.trim().isNotEmpty) {
      return;
    }
    _selectedOptionValue = options.first.value;
  }

  Future<bool> _persistResponseStatus(
    String status,
    List<String> answers, {
    String? submittedAction,
    String? actionResult,
    bool? resolved,
    String? expectedIdentity,
  }) async {
    if (!mounted) {
      return false;
    }
    final requestIdentity =
        expectedIdentity ?? _requestStorageIdentity(widget.cardData);
    final current = _requestSnapshotForIdentity(requestIdentity);
    if (current == null) {
      return false;
    }
    final currentStatus = _cardStatus(current);
    final currentIsTerminal = _isTerminalRequestStatus(currentStatus);
    final requestedWouldReplaceTerminal =
        currentIsTerminal && currentStatus != status;
    if (requestedWouldReplaceTerminal) {
      await _persistTerminalSnapshot(current);
      return false;
    }
    final snapshot = Map<String, dynamic>.from(current)
      ..['status'] = status
      ..['submittedAnswers'] = answers;
    if (submittedAction != null && submittedAction.isNotEmpty) {
      snapshot['submittedAction'] = submittedAction;
    }
    if (actionResult != null && actionResult.isNotEmpty) {
      snapshot['actionResult'] = actionResult;
    }
    if (resolved != null) {
      snapshot['resolved'] = resolved;
    }
    if (_isTerminalRequestStatus(status)) {
      // A terminal snapshot was derived while this State was still mounted.
      // Finish both writes even if disposal happens during the first await so
      // history and the response cache cannot disagree about the terminal.
      await _persistTerminalSnapshot(snapshot);
      if (!mounted) {
        return false;
      }
    } else {
      await _persistConversationSnapshot(snapshot);
      if (!mounted) {
        return false;
      }
      await _persistStorageSnapshot(snapshot);
      if (!mounted) {
        return false;
      }
    }
    final terminalCorrection = _terminalCorrectionAfter(
      requestIdentity,
      snapshot,
    );
    if (terminalCorrection != null) {
      await _persistTerminalSnapshot(terminalCorrection);
      return false;
    }
    return _hasRequestIdentity(requestIdentity) &&
        !_hasTerminalRequestStatus(widget.cardData);
  }

  Map<String, dynamic>? _requestSnapshotForIdentity(String identity) {
    if (!_hasRequestIdentity(identity)) {
      return null;
    }
    return Map<String, dynamic>.from(widget.cardData);
  }

  Map<String, dynamic>? _terminalCorrectionAfter(
    String identity,
    Map<String, dynamic> persisted,
  ) {
    final current = _requestSnapshotForIdentity(identity);
    if (current == null) {
      return null;
    }
    final currentStatus = _cardStatus(current);
    if (!_isTerminalRequestStatus(currentStatus) ||
        currentStatus == _cardStatus(persisted)) {
      return null;
    }
    return current;
  }

  Future<void> _persistConversationSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final conversationId = _asInt(snapshot['conversationId']);
    final cardId = (snapshot['cardId'] ?? snapshot['id'] ?? '')
        .toString()
        .trim();
    if (conversationId == null || cardId.isEmpty) {
      return;
    }
    try {
      await ConversationHistoryService.upsertConversationUiCard(
        conversationId,
        entryId: cardId,
        cardData: snapshot,
        createdAtMillis: _asInt(snapshot['startTime']),
        mode: ConversationMode.codex,
      );
    } catch (_) {
      // The server response already succeeded. A local history write failure
      // must not make the approval actionable again.
    }
  }

  Future<void> _persistStorageSnapshot(Map<String, dynamic> snapshot) async {
    try {
      final identity = _requestStorageIdentity(snapshot);
      final submittedAction = _firstText([snapshot['submittedAction']]);
      final actionResult = _firstText([snapshot['actionResult']]);
      await StorageService.setString(
        _requestStorageKey(snapshot),
        jsonEncode(<String, dynamic>{
          'identity': identity,
          'status': _cardStatus(snapshot),
          'answers': _stringList(snapshot['submittedAnswers']),
          if (submittedAction != null) 'submittedAction': submittedAction,
          if (actionResult != null) 'actionResult': actionResult,
          if (snapshot.containsKey('resolved'))
            'resolved': snapshot['resolved'],
        }),
      );
    } catch (_) {
      return;
    }
  }

  Future<void> _persistTerminalSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    await _persistConversationSnapshot(snapshot);
    await _persistStorageSnapshot(snapshot);
  }
}

class _RequestOptionTile extends StatelessWidget {
  const _RequestOptionTile({
    required this.index,
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int index;
  final _RequestOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final foreground = enabled ? palette.textPrimary : palette.textTertiary;
    final secondary = enabled ? palette.textSecondary : palette.textTertiary;
    final selectedTextColor = context.isDarkTheme
        ? palette.surfacePrimary
        : Colors.white;
    final selectedCircleColor = context.isDarkTheme
        ? palette.textPrimary
        : const Color(0xFF20242B);
    final unselectedCircleBorder = context.isDarkTheme
        ? palette.borderSubtle
        : const Color(0xFFDADDE2);
    return Material(
      key: ValueKey('codex-request-option-row-$index'),
      color: selected
          ? (context.isDarkTheme
                ? palette.surfaceElevated.withValues(alpha: 0.82)
                : const Color(0xFFF1F1F2))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? selectedCircleColor : Colors.transparent,
                  border: selected
                      ? null
                      : Border.all(color: unselectedCircleBorder),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: selected ? selectedTextColor : secondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                        height: 1.25,
                      ),
                    ),
                    if (option.description.isNotEmpty)
                      Text(
                        option.description,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                          height: 1.25,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomAnswerInput extends StatelessWidget {
  const _CustomAnswerInput({
    required this.inputKey,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onTap,
    required this.onChanged,
  });

  final Key inputKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isEnglish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'en';
    final hint = isEnglish
        ? 'No, tell Codex how to adjust'
        : '否，请告知 Codex 如何调整';
    final view = View.of(context);
    final viewKeyboardInset = view.viewInsets.bottom / view.devicePixelRatio;
    final mediaQueryKeyboardInset =
        MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0.0;
    final keyboardInset = viewKeyboardInset > mediaQueryKeyboardInset
        ? viewKeyboardInset
        : mediaQueryKeyboardInset;

    return KeyedSubtree(
      key: inputKey,
      child: SizedBox(
        key: const ValueKey('codex-request-custom-answer-input'),
        width: double.infinity,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          minLines: 1,
          maxLines: 1,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          scrollPhysics: const ClampingScrollPhysics(),
          scrollPadding: EdgeInsets.only(top: 24, bottom: keyboardInset + 96),
          onTap: onTap,
          onChanged: onChanged,
          textCapitalization: TextCapitalization.sentences,
          style: context.omniInputTextStyle,
          decoration: InputDecoration(
            labelText: hint,
            hintText: isEnglish ? 'Describe the adjustment' : '请输入调整说明',
          ),
        ),
      ),
    );
  }
}

class _RequestFooter extends StatelessWidget {
  const _RequestFooter({
    required this.kind,
    required this.status,
    required this.answers,
    required this.submittedAction,
    required this.isPending,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onAccept,
    required this.onDecline,
    required this.onIgnore,
    required this.onSubmit,
  });

  final String kind;
  final String status;
  final List<String> answers;
  final String? submittedAction;
  final bool isPending;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onIgnore;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final isEnglish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'en';
    if (isSubmitting) {
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.accentPrimary,
          ),
        ),
      );
    }
    if (status != 'pending') {
      final visibleAction =
          answers.isNotEmpty && submittedAction == 'submitted'
          ? null
          : submittedAction;
      final statusLabel = switch (status) {
        'response_sent' when submittedAction == 'handled_elsewhere' =>
          isEnglish
              ? 'Handled in another view — waiting for server'
              : '已在另一视图响应，等待服务端确认',
        'response_sent' => isEnglish
            ? 'Response sent${visibleAction == null ? '' : ': $visibleAction'}'
            : '已发送响应${visibleAction == null ? '' : '：$visibleAction'}',
        'resolved' => isEnglish ? 'Resolved' : '已处理',
        'invalidated' => isEnglish
            ? 'Expired — retry the action'
            : '已失效，请重新触发',
        _ => status,
      };
      return Text(
        answers.isEmpty ? statusLabel : '$statusLabel: ${answers.join(', ')}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.textSecondary,
        ),
      );
    }
    if (kind == 'approval') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: isPending ? onDecline : null,
            child: Text(isEnglish ? 'Decline' : '拒绝'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: isPending ? onAccept : null,
            child: Text(isEnglish ? 'Accept' : '接受'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: isPending ? onIgnore : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            foregroundColor: palette.textSecondary,
            disabledForegroundColor: palette.textTertiary,
          ),
          child: Text(
            isEnglish ? 'Ignore' : '忽略',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: canSubmit ? onSubmit : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            backgroundColor: const Color(0xFF2D99FF),
            disabledBackgroundColor: context.isDarkTheme
                ? palette.surfaceElevated
                : const Color(0xFFE2E5E9),
            foregroundColor: Colors.white,
            disabledForegroundColor: palette.textTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Text(
            isEnglish ? 'Submit ↵' : '提交 ↵',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _RequestOption {
  const _RequestOption({
    required this.label,
    required this.value,
    this.description = '',
  });

  final String label;
  final String value;
  final String description;
}

List<_RequestOption> _resolveRequestOptions(Map<String, dynamic> cardData) {
  final raw = _decodeRawParams(cardData['rawParamsJson']);
  final questionId = (cardData['questionId'] ?? '').toString().trim();
  final question = _resolveQuestion(raw, questionId);
  final optionSource =
      question?['options'] ??
      question?['choices'] ??
      question?['items'] ??
      raw['options'] ??
      raw['choices'];
  if (optionSource is! List) {
    return const <_RequestOption>[];
  }
  final seen = <String>{};
  final options = <_RequestOption>[];
  for (final item in optionSource) {
    final option = _requestOptionFromValue(item);
    if (option == null || !seen.add(option.value)) {
      continue;
    }
    options.add(option);
  }
  return options;
}

Map<String, dynamic> _decodeRawParams(dynamic rawParamsJson) {
  final raw = rawParamsJson?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return const <String, dynamic>{};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

Map<String, dynamic>? _resolveQuestion(
  Map<String, dynamic> raw,
  String questionId,
) {
  final questions = raw['questions'];
  if (questions is! List || questions.isEmpty) {
    return null;
  }
  for (final item in questions) {
    final map = _asStringMap(item);
    if (map == null) {
      continue;
    }
    final id = (map['id'] ?? map['questionId'] ?? '').toString();
    if (questionId.isNotEmpty && id == questionId) {
      return map;
    }
  }
  return _asStringMap(questions.first);
}

_RequestOption? _requestOptionFromValue(dynamic value) {
  if (value is String || value is num || value is bool) {
    final label = value.toString().trim();
    return label.isEmpty ? null : _RequestOption(label: label, value: label);
  }
  final map = _asStringMap(value);
  if (map == null) {
    return null;
  }
  final label =
      _firstText([
        map['label'],
        map['title'],
        map['name'],
        map['value'],
        map['id'],
      ]) ??
      '';
  if (label.isEmpty) {
    return null;
  }
  final optionValue =
      _firstText([map['value'], map['id'], map['label']]) ?? label;
  final description =
      _firstText([map['description'], map['detail'], map['subtitle']]) ?? '';
  return _RequestOption(
    label: label,
    value: optionValue,
    description: description,
  );
}

String _requestStorageKey(Map<String, dynamic> cardData) {
  return 'codex_request_response.${_requestStorageIdentity(cardData)}';
}

String _requestStorageIdentity(Map<String, dynamic> cardData) {
  final parts = <String>[
    (cardData['sessionGeneration'] ?? '').toString().trim(),
    (cardData['serverRequestMethod'] ?? '').toString().trim(),
    _requestIdStorageKey(cardData['requestId']) ?? '',
    (cardData['cardId'] ?? cardData['id'] ?? '').toString().trim(),
    (cardData['questionId'] ?? '').toString().trim(),
    (cardData['startTime'] ?? '').toString().trim(),
  ].where((part) => part.isNotEmpty).toList(growable: false);
  if (parts.isEmpty) {
    return 'unknown';
  }
  return parts.join('.');
}

String _requestRenderSignature(Map<String, dynamic> cardData) {
  return [
    _requestStorageIdentity(cardData),
    _cardStatus(cardData),
    (cardData['rawParamsJson'] ?? '').toString(),
  ].join('|');
}

String _cardStatus(Map<String, dynamic> cardData) {
  final normalized = (cardData['status'] ?? 'pending')
      .toString()
      .trim()
      .toLowerCase();
  return normalized.isEmpty ? 'pending' : normalized;
}

bool _isTerminalRequestStatus(String? status) {
  return status == 'submitted' ||
      status == 'ignored' ||
      status == 'accepted' ||
      status == 'declined' ||
      status == 'resolved' ||
      status == 'invalidated';
}

bool _hasTerminalRequestStatus(Map<String, dynamic> cardData) {
  return _isTerminalRequestStatus(_cardStatus(cardData));
}

bool _isRestorableRequestStatus(String? status) {
  return _isTerminalRequestStatus(status) || status == 'response_sent';
}

bool _hasCompleteServerRequestIdentity(Map<String, dynamic> cardData) {
  return _requestIdStorageKey(cardData['requestId']) != null &&
      _requestSessionGeneration(cardData) != null &&
      _requestServerMethod(cardData) != null;
}

String? _requestIdStorageKey(dynamic requestId) {
  if (requestId is String) {
    return 'string:$requestId';
  }
  if (requestId is num) {
    return 'number:$requestId';
  }
  return null;
}

int? _requestSessionGeneration(Map<String, dynamic> cardData) {
  final value = _asInt(cardData['sessionGeneration']);
  return value != null && value > 0 ? value : null;
}

String? _requestServerMethod(Map<String, dynamic> cardData) {
  final method = cardData['serverRequestMethod']?.toString().trim() ?? '';
  return method.isEmpty ? null : method;
}

enum _ServerRequestFailureDisposition {
  invalidated,
  handledElsewhere,
  retryable,
}

_ServerRequestFailureDisposition _serverRequestFailureDisposition(
  Object error,
) {
  if (error is PlatformException) {
    final code = error.code.trim().toUpperCase();
    return switch (code) {
      'CODEX_SERVER_REQUEST_GENERATION_REQUIRED' ||
      'CODEX_STALE_SERVER_REQUEST' ||
      'CODEX_SERVER_REQUEST_METHOD_REQUIRED' ||
      'CODEX_SERVER_REQUEST_METHOD_MISMATCH' ||
      'CODEX_SERVER_REQUEST_NOT_PENDING' =>
        _ServerRequestFailureDisposition.invalidated,
      'CODEX_SERVER_REQUEST_ALREADY_RESPONDED' =>
        _ServerRequestFailureDisposition.handledElsewhere,
      'CODEX_SERVER_DISCONNECTED' ||
      'CODEX_SERVER_RESPONSE_WRITE_FAILED' =>
        _ServerRequestFailureDisposition.retryable,
      _ => _ServerRequestFailureDisposition.retryable,
    };
  }
  final text = error.toString().toLowerCase();
  if (text.contains('session generation') ||
      text.contains('invalidated') ||
      text.contains('stale server request') ||
      text.contains('no longer pending')) {
    return _ServerRequestFailureDisposition.invalidated;
  }
  return _ServerRequestFailureDisposition.retryable;
}

@visibleForTesting
String serverRequestFailureDispositionForTesting(Object error) {
  return switch (_serverRequestFailureDisposition(error)) {
    _ServerRequestFailureDisposition.invalidated => 'invalidated',
    _ServerRequestFailureDisposition.handledElsewhere =>
      'handled_elsewhere',
    _ServerRequestFailureDisposition.retryable => 'retryable',
  };
}

String _requestSubmitErrorText(Object error) {
  final raw = error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();
  final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final text = normalized.isEmpty ? 'Failed to send response. Retry.' : normalized;
  return text.length <= 180 ? text : '${text.substring(0, 180)}…';
}

String _requestVisibleDetail(String title, String detail) {
  final normalizedTitle = _normalizeComparableText(title);
  final normalizedDetail = _normalizeComparableText(detail);
  if (normalizedDetail.isEmpty || normalizedDetail == normalizedTitle) {
    return '';
  }
  return detail;
}

String _normalizeComparableText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, nestedValue) => MapEntry(key.toString(), nestedValue));
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _firstText(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
