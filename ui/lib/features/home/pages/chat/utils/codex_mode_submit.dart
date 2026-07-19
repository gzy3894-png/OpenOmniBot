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

/// Session tip: 计划模式 / Plan mode on/off (B7 product name).
String codexSessionTipPlan({required bool enabled, required bool isEnglish}) {
  if (enabled) {
    return isEnglish ? 'Plan mode on' : '已开启计划模式';
  }
  return isEnglish ? 'Plan mode off' : '已关闭计划模式';
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

/// Planned composer submit after slash / skill-mention normalization.
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

/// Plans a Codex composer submit from raw input.
///
/// Priority:
/// 1. Leading `/` slash → [resolveCodexSlashSubmitIntent]
/// 2. `@skill` mentions → [CodexSlashSubmitKind.startSkill] / `/skill ...`
/// 3. Otherwise plain message ([handled] = false, kind none)
///
/// An active thread Goal is deliberately not an input to this planner.
/// Updating a Goal requires the independent editor or an explicit
/// `/goal <objective>` command, so ordinary composer text always remains a
/// normal user turn.
///
/// [skillNames] is the known catalog used to recognize `@` tokens. When empty,
/// any `@token` is treated as a skill mention.
CodexComposerSubmit planCodexComposerSubmit(
  String rawText, {
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
    // B5 (plan layer): `/review <prompt>` keeps startReview + prompt value
    // (handler maps to custom.instructions; bare → uncommitted).
    // Bare `/review` still comes from [resolveCodexSlashSubmitIntent].
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
///
/// Display-facing and catalog-normalized form (no absolute path). Prefer
/// [buildCodexSkillActualText] for model/startTurn payloads (B3).
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

/// Prefer the shell-visible skill file path, then the app-local path (B3).
///
/// Empty when neither is set — callers should still send name + prompt.
String preferCodexSkillFilePath({
  String shellSkillFilePath = '',
  String skillFilePath = '',
}) {
  final shell = shellSkillFilePath.trim();
  if (shell.isNotEmpty) {
    return shell;
  }
  return skillFilePath.trim();
}

/// Model/startTurn payload for skills: name + **implicit path** + optional 附言.
///
/// Bridge currently only accepts free-form [text], so path is embedded as a
/// readable `skill_path:` line. User bubbles must use [displayText] / raw
/// `@name 附言` instead — never this string.
///
/// [skillPathsByLowerName] keys are lower-cased skill names (or ids).
String buildCodexSkillActualText({
  required List<String> skillNames,
  String prompt = '',
  Map<String, String> skillPathsByLowerName = const <String, String>{},
}) {
  final names = skillNames
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toList(growable: false);
  final body = prompt.trim();
  if (names.isEmpty) {
    return buildCodexSkillCommand(skillNames: names, prompt: body);
  }

  final buffer = StringBuffer();
  for (var i = 0; i < names.length; i++) {
    final name = names[i];
    if (i > 0) {
      buffer.writeln();
    }
    buffer.write('/skill $name');
    final path = (skillPathsByLowerName[name.toLowerCase()] ?? '').trim();
    if (path.isNotEmpty) {
      buffer.writeln();
      buffer.write('skill_path: $path');
    }
  }
  if (body.isNotEmpty) {
    buffer.writeln();
    buffer.write(body);
  }
  return buffer.toString();
}

/// Splits `/skill` args into leading skill name tokens (matched against
/// [knownSkillNames] when provided) and trailing prompt.
///
/// When [knownSkillNames] is empty, only the first whitespace-separated token
/// is treated as a skill name.
({List<String> skillNames, String prompt}) parseCodexSkillSlashArgs(
  String args, {
  Iterable<String> knownSkillNames = const <String>[],
}) {
  var rest = args.trim();
  if (rest.isEmpty) {
    return (skillNames: const <String>[], prompt: '');
  }

  final known = <String, String>{};
  for (final name in knownSkillNames) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    known[trimmed.toLowerCase()] = trimmed;
  }
  final knownLowerSorted = known.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  final names = <String>[];
  if (knownLowerSorted.isNotEmpty) {
    while (rest.isNotEmpty) {
      final lower = rest.toLowerCase();
      String? matched;
      var matchedLen = 0;
      for (final key in knownLowerSorted) {
        if (!lower.startsWith(key)) {
          continue;
        }
        final end = key.length;
        if (end < rest.length && !RegExp(r'\s').hasMatch(rest[end])) {
          continue;
        }
        matched = known[key];
        matchedLen = end;
        break;
      }
      if (matched == null) {
        break;
      }
      names.add(matched);
      rest = rest.substring(matchedLen).trimLeft();
    }
  } else {
    final match = RegExp(r'^(\S+)(?:\s+(.*))?$', dotAll: true).firstMatch(rest);
    if (match != null) {
      final name = (match.group(1) ?? '').trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
      rest = (match.group(2) ?? '').trim();
    }
  }

  return (
    skillNames: List<String>.unmodifiable(names),
    prompt: rest.trim(),
  );
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
