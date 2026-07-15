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

  group('codexFastModeHint', () {
    test('exact short PO copy for on/off ZH/EN', () {
      expect(
        kCodexFastModeHintOnZh,
        '已开启 Fast：1.5× 速度；计费约 1.5–2×。',
      );
      expect(
        kCodexFastModeHintOffZh,
        '已关闭 Fast：恢复标准速度与计费。',
      );
      expect(
        kCodexFastModeHintOnEn,
        'Fast on: ~1.5× speed; billing ~1.5–2×.',
      );
      expect(
        kCodexFastModeHintOffEn,
        'Fast off: standard speed and billing.',
      );

      expect(goalClearCommand, '/goal clear');
      expect(kCodexGoalClearCommand, '/goal clear');
      expect(codexFastModeHint(isEnglish: true), kCodexFastModeHintEn);
      expect(codexFastModeHint(isEnglish: false), kCodexFastModeHintZh);
      expect(codexFastModeHint(isEnglish: true), kCodexFastModeHintOnEn);
      expect(codexFastModeHint(isEnglish: false), kCodexFastModeHintOnZh);
      expect(codexFastModeHintOn(isEnglish: true), kCodexFastModeHintOnEn);
      expect(codexFastModeHintOff(isEnglish: false), kCodexFastModeHintOffZh);

      // On tips: short PO copy — 1.5× speed + 1.5–2× billing (no priority-lane essay)
      expect(kCodexFastModeHintOnEn, contains('1.5'));
      expect(kCodexFastModeHintOnEn.toLowerCase(), contains('billing'));
      expect(kCodexFastModeHintOnEn, isNot(contains('priority')));
      expect(kCodexFastModeHintOnZh, contains('1.5'));
      expect(kCodexFastModeHintOnZh, contains('计费'));
      expect(kCodexFastModeHintOnZh, isNot(contains('优先通道')));

      // Off tips via enabled: false
      expect(
        codexFastModeHint(isEnglish: true, enabled: false),
        kCodexFastModeHintOffEn,
      );
      expect(
        codexFastModeHint(isEnglish: false, enabled: false),
        kCodexFastModeHintOffZh,
      );
      expect(kCodexFastModeHintOffEn.toLowerCase(), contains('off'));
      expect(kCodexFastModeHintOffEn.toLowerCase(), contains('billing'));
      expect(kCodexFastModeHintOffZh, contains('关闭'));
      expect(kCodexFastModeHintOffZh, contains('计费'));
    });
  });

  group('codexSessionTip helpers', () {
    test('model', () {
      expect(
        codexSessionTipModel('gpt-5.1', isEnglish: false),
        '已切换模型：gpt-5.1',
      );
      expect(
        codexSessionTipModel('gpt-5.1', isEnglish: true),
        'Model: gpt-5.1',
      );
    });

    test('effort', () {
      expect(
        codexSessionTipEffort('xhigh', isEnglish: false),
        '已切换思考等级：xhigh',
      );
      expect(
        codexSessionTipEffort('medium', isEnglish: true),
        'Reasoning: medium',
      );
    });

    test('review started', () {
      expect(
        codexSessionTipReviewStarted(isEnglish: false),
        '已开始审查',
      );
      expect(
        codexSessionTipReviewStarted(isEnglish: true),
        'Review started',
      );
    });

    test('skill inserted adds @ when missing', () {
      expect(
        codexSessionTipSkillInserted('review-pr', isEnglish: false),
        '已插入技能：@review-pr',
      );
      expect(
        codexSessionTipSkillInserted('@ship', isEnglish: true),
        'Skill inserted: @ship',
      );
    });

    test('plan on/off', () {
      expect(
        codexSessionTipPlan(enabled: true, isEnglish: false),
        '已开启 Plan',
      );
      expect(
        codexSessionTipPlan(enabled: false, isEnglish: false),
        '已关闭 Plan',
      );
      expect(
        codexSessionTipPlan(enabled: true, isEnglish: true),
        'Plan on',
      );
      expect(
        codexSessionTipPlan(enabled: false, isEnglish: true),
        'Plan off',
      );
    });

    test('permission', () {
      expect(
        codexSessionTipPermission('完整访问', isEnglish: false),
        '权限：完整访问',
      );
      expect(
        codexSessionTipPermission('Full Access', isEnglish: true),
        'Permission: Full Access',
      );
    });
  });
}
