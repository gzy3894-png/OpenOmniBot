/// Pure helpers for Codex `@skill` mention tokens in composer text.
///
/// Tokens look like `@skill-name` (no spaces). When [knownSkillNames] is given,
/// only names that match a known skill (case-insensitive) are treated as
/// mentions; otherwise any contiguous non-space run after `@` counts.
library;

/// One `@skill` mention found in composer text.
class CodexSkillMention {
  const CodexSkillMention({
    required this.name,
    required this.start,
    required this.end,
    required this.raw,
  });

  /// Canonical skill name (prefers known catalog casing when matched).
  final String name;

  /// Inclusive start index of `@` in the original string.
  final int start;

  /// Exclusive end index of the token in the original string.
  final int end;

  /// Exact substring including leading `@`.
  final String raw;
}

/// Result of splitting skill mentions from plain body text.
class CodexSkillTokenParseResult {
  const CodexSkillTokenParseResult({
    required this.mentions,
    required this.plainText,
    required this.skillNames,
  });

  final List<CodexSkillMention> mentions;

  /// Original text with skill mention tokens removed and whitespace collapsed
  /// to single spaces (trimmed).
  final String plainText;

  /// Ordered unique skill names from [mentions].
  final List<String> skillNames;
}

final RegExp _skillTokenBody = RegExp(r'[^\s@]+');

/// Parses `@技能名` tokens and separates them from ordinary text.
///
/// - Mentions must be `@` at start-of-string or after whitespace.
/// - Email-like `user@host` is ignored (no whitespace before `@`).
/// - When [knownSkillNames] is non-empty, only catalog matches count
///   (longest name wins on ambiguity).
CodexSkillTokenParseResult parseCodexSkillTokens(
  String rawText, {
  Iterable<String> knownSkillNames = const <String>[],
}) {
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

  final mentions = <CodexSkillMention>[];
  final buffer = StringBuffer();
  var i = 0;
  final text = rawText;

  while (i < text.length) {
    final ch = text[i];
    if (ch == '@' && _isSkillAtBoundary(text, i)) {
      final afterAt = i + 1;
      String? matchedName;
      var matchedEnd = afterAt;

      if (knownLowerSorted.isNotEmpty) {
        final restLower = text.substring(afterAt).toLowerCase();
        for (final key in knownLowerSorted) {
          if (restLower.startsWith(key)) {
            final end = afterAt + key.length;
            if (end == text.length || _isTokenEnd(text[end])) {
              matchedName = known[key];
              matchedEnd = end;
              break;
            }
          }
        }
      } else {
        final match = _skillTokenBody.matchAsPrefix(text, afterAt);
        if (match != null) {
          matchedName = match.group(0);
          matchedEnd = match.end;
        }
      }

      if (matchedName != null && matchedName.isNotEmpty) {
        mentions.add(
          CodexSkillMention(
            name: matchedName,
            start: i,
            end: matchedEnd,
            raw: text.substring(i, matchedEnd),
          ),
        );
        if (buffer.isNotEmpty && !buffer.toString().endsWith(' ')) {
          buffer.write(' ');
        }
        i = matchedEnd;
        continue;
      }
    }

    buffer.write(ch);
    i += 1;
  }

  final plain = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  final names = <String>[];
  final seen = <String>{};
  for (final m in mentions) {
    final key = m.name.toLowerCase();
    if (seen.add(key)) {
      names.add(m.name);
    }
  }

  return CodexSkillTokenParseResult(
    mentions: List<CodexSkillMention>.unmodifiable(mentions),
    plainText: plain,
    skillNames: List<String>.unmodifiable(names),
  );
}

/// Formats a visible composer token for a selected skill.
String formatCodexSkillMentionToken(String skillName) {
  final name = skillName.trim();
  if (name.isEmpty) {
    return '';
  }
  return name.startsWith('@') ? name : '@$name';
}

bool _isSkillAtBoundary(String text, int atIndex) {
  if (atIndex <= 0) {
    return true;
  }
  return RegExp(r'\s').hasMatch(text[atIndex - 1]);
}

bool _isTokenEnd(String ch) {
  return RegExp(r'\s').hasMatch(ch) || ch == '@';
}
