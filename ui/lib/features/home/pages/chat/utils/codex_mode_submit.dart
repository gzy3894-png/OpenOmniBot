import 'codex_skill_tokens.dart';
import 'codex_slash_commands.dart';

/// Fast-mode session tip (EN): shown when Fast is turned on.
/// Speed and billing are separate clauses (no ambiguous shared multiplier).
const String kCodexFastModeHintOnEn =
    'Fast on: ~1.5× faster replies; billing ~1.5–2× Standard.';

/// Fast-mode session tip (ZH): shown when Fast is turned on.
const String kCodexFastModeHintOnZh =
    '已开启 Fast：响应更快（约 1.5×），计费约为标准的 1.5–2 倍。';

/// Fast-mode session tip (EN): shown when Fast is turned off.
const String kCodexFastModeHintOffEn =
    'Fast off: standard speed and standard billing.';

/// Fast-mode session tip (ZH): shown when Fast is turned off.
const String kCodexFastModeHintOffZh = '已关闭 Fast：已恢复标准速度与标准计费。';

/// Backward-compatible alias for [kCodexFastModeHintOnEn].
const String kCodexFastModeHintEn = kCodexFastModeHintOnEn;

/// Backward-compatible alias for [kCodexFastModeHintOnZh].
const String kCodexFastModeHintZh = kCodexFastModeHintOnZh;

/// Localized Fast tip for transcript insertion.
///
/// [enabled] true → on tip (faster replies + higher billing, separate clauses);
/// false → off tip (standard speed and standard billing).
/// Defaults to true so existing `codexFastModeHint(isEnglish: …)` call sites stay valid.
String codexFastModeHint({required bool isEnglish, bool enabled = true}) {
  if (enabled) {
    return isEnglish ? kCodexFastModeHintOnEn : kCodexFastModeHintOnZh;
  }
  return isEnglish ? kCodexFastModeHintOffEn : kCodexFastModeHintOffZh;
}

/// Convenience: Fast-on tip.
String codexFastModeHintOn({required bool isEnglish}) =>
    codexFastModeHint(isEnglish: isEnglish, enabled: true);

/// Convenience: Fast-off tip.
String codexFastModeHintOff({required bool isEnglish}) =>
    codexFastModeHint(isEnglish: isEnglish, enabled: false);

/// Session tip: model switch.
String codexSessionTipModel(String modelId, {required bool isEnglish}) {
  final id = modelId.trim();
  return isEnglish ? 'Model: $id' : '已切换模型：$id';
}

/// Session tip: reasoning / effort level switch.
String codexSessionTipEffort(String effort, {required bool isEnglish}) {
  final level = effort.trim();
  return isEnglish ? 'Reasoning: $level' : '已切换思考等级：$level';
}

/// Session tip: review started.
String codexSessionTipReviewStarted({required bool isEnglish}) =>
    isEnglish ? 'Review started' : '已开始审查';

/// Session tip: skill inserted into composer (e.g. from @ panel).
String codexSessionTipSkillInserted(String skillName, {required bool isEnglish}) {
  final name = skillName.trim();
  final token = name.startsWith('@') ? name : '@$name';
  return isEnglish ? 'Skill inserted: $token' : '已插入技能：$token';
}

/// Session tip: Plan mode on/off.
String codexSessionTipPlan({required bool enabled, required bool isEnglish}) {
  if (enabled) {
    return isEnglish ? 'Plan on' : '已开启 Plan';
  }
  return isEnglish ? 'Plan off' : '已关闭 Plan';
}

/// Session tip: permission mode change.
String codexSessionTipPermission(String label, {required bool isEnglish}) {
  final value = label.trim();
  return isEnglish ? 'Permission: $value' : '权限：$value';
}

/// Display form for a goal objective (e.g. transcript / chrome).
/// Planning semantics for setGoal remain in [planCodexComposerSubmit].
String formatCodexGoalCommand(String objective) {
  final trimmed = objective.trim();
  return trimmed.isEmpty ? '/goal' : '/goal $trimmed';
}

/// Command string handlers should send when turning goal mode off.
const String kCodexGoalClearCommand = '/goal clear';

/// Alias for [kCodexGoalClearCommand] (handler-friendly name).
String get goalClearCommand => kCodexGoalClearCommand;

/// Planned composer submit after goal-mode / skill-mention normalization.
class CodexComposerSubmit {
  const CodexComposerSubmit({
    required this.intent,
    required this.normalizedText,
    this.skillNames = const <String>[],
    this.plainText = '',
    this.handled = true,
  });

  /// Structured intent for M4 switch handling.
  final CodexSlashSubmitIntent intent;

  /// Text to send / display as the effective command or message body.
  /// For setGoal / startSkill this is the normalized slash form.
  final String normalizedText;

  /// Skill names extracted from `@` mentions (if any).
  final List<String> skillNames;

  /// Body text with skill tokens stripped (and for goal, the objective).
  final String plainText;

  /// When false, caller should treat [normalizedText] as a normal user message.
  final bool handled;
}

/// Plans Codex composer submit from raw input + session mode flags.
///
/// Priority:
/// 1. Leading `/` slash → [resolveCodexSlashSubmitIntent] (unchanged behavior)
/// 2. `@skill` mentions → [CodexSlashSubmitKind.startSkill] / `/skill ...`
/// 3. [goalModeEnabled] + non-empty non-slash body → setGoal / `/goal <text>`
/// 4. Otherwise plain message ([handled] = false, kind none)
///
/// [skillNames] is the known catalog used to recognize `@` tokens. When empty,
/// any `@token` is treated as a skill mention.
CodexComposerSubmit planCodexComposerSubmit(
  String rawText, {
  required bool goalModeEnabled,
  List<String> skillNames = const <String>[],
}) {
  final trimmed = rawText.trim();
  if (trimmed.isEmpty) {
    return const CodexComposerSubmit(
      intent: CodexSlashSubmitIntent(CodexSlashSubmitKind.none),
      normalizedText: '',
      handled: false,
    );
  }

  if (trimmed.startsWith('/')) {
    // R1 (plan layer): `/review <prompt>` keeps startReview + prompt value.
    // Bare `/review` still comes from [resolveCodexSlashSubmitIntent].
    // Full slash-table support for review args remains in codex_slash_commands
    // (M4 / shared utils outside this module lock).
    final reviewPrompt = _codexReviewPromptArg(trimmed);
    if (reviewPrompt != null) {
      return CodexComposerSubmit(
        intent: CodexSlashSubmitIntent(
          CodexSlashSubmitKind.startReview,
          value: reviewPrompt,
        ),
        normalizedText: trimmed,
        plainText: reviewPrompt,
        handled: true,
      );
    }

    final intent = resolveCodexSlashSubmitIntent(trimmed);
    return CodexComposerSubmit(
      intent: intent,
      normalizedText: trimmed,
      plainText: trimmed,
      handled: intent.kind != CodexSlashSubmitKind.none,
    );
  }

  final parsed = parseCodexSkillTokens(
    rawText,
    knownSkillNames: skillNames,
  );

  if (parsed.skillNames.isNotEmpty) {
    final command = buildCodexSkillCommand(
      skillNames: parsed.skillNames,
      prompt: parsed.plainText,
    );
    final intent = resolveCodexSlashSubmitIntent(command);
    return CodexComposerSubmit(
      intent: intent.kind == CodexSlashSubmitKind.startSkill
          ? intent
          : CodexSlashSubmitIntent(
              CodexSlashSubmitKind.startSkill,
              value: _skillCommandValue(
                skillNames: parsed.skillNames,
                prompt: parsed.plainText,
              ),
            ),
      normalizedText: command,
      skillNames: parsed.skillNames,
      plainText: parsed.plainText,
    );
  }

  if (goalModeEnabled) {
    final objective = trimmed;
    if (objective.isEmpty) {
      return const CodexComposerSubmit(
        intent: CodexSlashSubmitIntent(CodexSlashSubmitKind.showGoal),
        normalizedText: '/goal',
      );
    }
    final command = '/goal $objective';
    return CodexComposerSubmit(
      intent: CodexSlashSubmitIntent(
        CodexSlashSubmitKind.setGoal,
        value: objective,
      ),
      normalizedText: command,
      plainText: objective,
    );
  }

  return CodexComposerSubmit(
    intent: const CodexSlashSubmitIntent(CodexSlashSubmitKind.none),
    normalizedText: trimmed,
    plainText: trimmed,
    handled: false,
  );
}

/// Builds normalized `/skill` command text.
///
/// Format: `/skill <name>[ <name>...][ <prompt>]`
String buildCodexSkillCommand({
  required List<String> skillNames,
  String prompt = '',
}) {
  final names = skillNames
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList(growable: false);
  final body = prompt.trim();
  if (names.isEmpty) {
    return body.isEmpty ? '/skill' : '/skill $body';
  }
  final namePart = names.join(' ');
  if (body.isEmpty) {
    return '/skill $namePart';
  }
  return '/skill $namePart $body';
}

String _skillCommandValue({
  required List<String> skillNames,
  String prompt = '',
}) {
  final command = buildCodexSkillCommand(
    skillNames: skillNames,
    prompt: prompt,
  );
  if (command == '/skill') {
    return '';
  }
  return command.substring('/skill'.length).trim();
}

/// Returns non-empty prompt for `/review <prompt>`; null for bare `/review`
/// or non-review text.
String? _codexReviewPromptArg(String trimmed) {
  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('/review')) {
    return null;
  }
  if (lower == '/review') {
    return null;
  }
  if (!lower.startsWith('/review ')) {
    return null;
  }
  final prompt = trimmed.substring('/review'.length).trim();
  return prompt.isEmpty ? null : prompt;
}
