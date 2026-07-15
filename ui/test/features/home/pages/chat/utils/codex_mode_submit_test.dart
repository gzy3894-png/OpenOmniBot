import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/utils/codex_mode_submit.dart';
import 'package:ui/features/home/pages/chat/utils/codex_skill_tokens.dart';
import 'package:ui/features/home/pages/chat/utils/codex_slash_commands.dart';

void main() {
  group('parseCodexSkillTokens', () {
    test('splits @skill tokens from plain text', () {
      final parsed = parseCodexSkillTokens(
        'please @review-pr and @fix-tests now',
        knownSkillNames: const ['review-pr', 'fix-tests'],
      );
      expect(parsed.skillNames, ['review-pr', 'fix-tests']);
      expect(parsed.plainText, 'please and now');
      expect(parsed.mentions, hasLength(2));
    });

    test('ignores email-like at-signs', () {
      final parsed = parseCodexSkillTokens(
        'mail user@host.com and @ship',
        knownSkillNames: const ['ship'],
      );
      expect(parsed.skillNames, ['ship']);
      expect(parsed.plainText, 'mail user@host.com and');
    });

    test('only matches known catalog when provided', () {
      final parsed = parseCodexSkillTokens(
        '@ship it @unknown',
        knownSkillNames: const ['ship'],
      );
      expect(parsed.skillNames, ['ship']);
      expect(parsed.plainText, 'it @unknown');
    });
  });

  group('planCodexComposerSubmit', () {
    test('goal mode maps plain text to setGoal', () {
      final plan = planCodexComposerSubmit(
        'ship slash UX',
        goalModeEnabled: true,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.setGoal);
      expect(plan.intent.value, 'ship slash UX');
      expect(plan.normalizedText, '/goal ship slash UX');
      expect(plan.handled, isTrue);
    });

    test('goal mode does not rewrite leading slash', () {
      final plan = planCodexComposerSubmit(
        '/status',
        goalModeEnabled: true,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.showStatus);
      expect(plan.normalizedText, '/status');
    });

    test('skill mentions map to /skill', () {
      final plan = planCodexComposerSubmit(
        '@review-pr fix the flaky test',
        goalModeEnabled: false,
        skillNames: const ['review-pr'],
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startSkill);
      expect(plan.normalizedText, '/skill review-pr fix the flaky test');
      expect(plan.skillNames, ['review-pr']);
      expect(plan.plainText, 'fix the flaky test');
    });

    test('skill mentions win over goal mode', () {
      final plan = planCodexComposerSubmit(
        '@ship tomorrow',
        goalModeEnabled: true,
        skillNames: const ['ship'],
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startSkill);
      expect(plan.normalizedText, '/skill ship tomorrow');
    });

    test('plain message when no mode', () {
      final plan = planCodexComposerSubmit(
        'hello',
        goalModeEnabled: false,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.none);
      expect(plan.handled, isFalse);
      expect(plan.normalizedText, 'hello');
    });
  });

  test('goal clear and fast hint constants', () {
    expect(goalClearCommand, '/goal clear');
    expect(kCodexGoalClearCommand, '/goal clear');
    expect(codexFastModeHint(isEnglish: true), kCodexFastModeHintEn);
    expect(codexFastModeHint(isEnglish: false), kCodexFastModeHintZh);
    expect(kCodexFastModeHintEn.toLowerCase(), contains('latency'));
    expect(kCodexFastModeHintZh, contains('延迟'));
  });
}
