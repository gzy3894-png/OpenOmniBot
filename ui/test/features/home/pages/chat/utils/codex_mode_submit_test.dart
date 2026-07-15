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

    // S1 regression: skill name + trailing prompt must both survive parse.
    test('S1 keeps skillNames and plainText for @find-install-skills prompt', () {
      final parsed = parseCodexSkillTokens(
        '@find-install-skills 帮我安装 xxx',
        knownSkillNames: const ['find-install-skills'],
      );
      expect(parsed.skillNames, ['find-install-skills']);
      expect(parsed.plainText, '帮我安装 xxx');
      expect(parsed.mentions, hasLength(1));
      expect(parsed.mentions.single.raw, '@find-install-skills');
    });

    test('S1 multi @a @b keeps trailing prompt', () {
      final parsed = parseCodexSkillTokens(
        '@a @b 附言内容',
        knownSkillNames: const ['a', 'b'],
      );
      expect(parsed.skillNames, ['a', 'b']);
      expect(parsed.plainText, '附言内容');
    });

    test('S1 plain sentence without @ is not a skill parse', () {
      final parsed = parseCodexSkillTokens(
        '帮我安装 xxx',
        knownSkillNames: const ['find-install-skills'],
      );
      expect(parsed.skillNames, isEmpty);
      expect(parsed.plainText, '帮我安装 xxx');
    });
  });


  group('buildCodexSkillActualText B3', () {
    test('embeds shellSkillFilePath and keeps prompt', () {
      final actual = buildCodexSkillActualText(
        skillNames: const ['find-install-skills'],
        prompt: '这个技能呢',
        skillPathsByLowerName: const {
          'find-install-skills':
              '/workspace/.omnibot/skills/find-install-skills/SKILL.md',
        },
      );
      expect(actual, contains('/skill find-install-skills'));
      expect(
        actual,
        contains(
          'skill_path: /workspace/.omnibot/skills/find-install-skills/SKILL.md',
        ),
      );
      expect(actual, contains('这个技能呢'));
      // path must not look like a bare @ bubble
      expect(actual.startsWith('@'), isFalse);
    });

    test('preferCodexSkillFilePath prefers shell path', () {
      expect(
        preferCodexSkillFilePath(
          shellSkillFilePath: '/shell/path/SKILL.md',
          skillFilePath: '/app/path/SKILL.md',
        ),
        '/shell/path/SKILL.md',
      );
      expect(
        preferCodexSkillFilePath(
          shellSkillFilePath: '',
          skillFilePath: '/app/path/SKILL.md',
        ),
        '/app/path/SKILL.md',
      );
    });

    test('parseCodexSkillSlashArgs splits known names and prompt', () {
      final parsed = parseCodexSkillSlashArgs(
        'find-install-skills 这个技能呢',
        knownSkillNames: const ['find-install-skills'],
      );
      expect(parsed.skillNames, ['find-install-skills']);
      expect(parsed.prompt, '这个技能呢');
    });
  });

  group('buildCodexSkillCommand', () {
    test('S1 command includes skill name and prompt', () {
      expect(
        buildCodexSkillCommand(
          skillNames: const ['find-install-skills'],
          prompt: '帮我安装 xxx',
        ),
        '/skill find-install-skills 帮我安装 xxx',
      );
    });

    test('S1 multi-skill command keeps prompt', () {
      expect(
        buildCodexSkillCommand(
          skillNames: const ['a', 'b'],
          prompt: '附言内容',
        ),
        '/skill a b 附言内容',
      );
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

    test('B1 goal mode bare slash is not slash dirty path', () {
      final plan = planCodexComposerSubmit(
        '/',
        goalModeEnabled: true,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.showGoal);
      expect(plan.normalizedText, '/goal');
      expect(plan.handled, isTrue);
    });

    test('B1 goal mode bare slash with spaces is not slash', () {
      final plan = planCodexComposerSubmit(
        '/  ',
        goalModeEnabled: true,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.showGoal);
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

    // S1 failure-reproduction / regression: name + prompt both retained.
    test('S1 plan keeps skillNames plainText and normalized with prompt', () {
      final plan = planCodexComposerSubmit(
        '@find-install-skills 帮我安装 xxx',
        goalModeEnabled: false,
        skillNames: const ['find-install-skills'],
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startSkill);
      expect(plan.skillNames, ['find-install-skills']);
      expect(plan.plainText, '帮我安装 xxx');
      expect(plan.normalizedText, '/skill find-install-skills 帮我安装 xxx');
      expect(plan.intent.value, 'find-install-skills 帮我安装 xxx');
      expect(plan.handled, isTrue);
    });

    test('S1 multi @a @b prompt still planned as /skill', () {
      final plan = planCodexComposerSubmit(
        '@a @b 附言内容',
        goalModeEnabled: false,
        skillNames: const ['a', 'b'],
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startSkill);
      expect(plan.skillNames, ['a', 'b']);
      expect(plan.plainText, '附言内容');
      expect(plan.normalizedText, '/skill a b 附言内容');
    });

    test('S1 plain sentence without @ does not start skill', () {
      final plan = planCodexComposerSubmit(
        '帮我安装 xxx',
        goalModeEnabled: false,
        skillNames: const ['find-install-skills'],
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.none);
      expect(plan.handled, isFalse);
      expect(plan.skillNames, isEmpty);
      expect(plan.normalizedText, '帮我安装 xxx');
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

    // R1 (plan-layer): bare vs prompted review.
    test('R1 bare /review is startReview without value', () {
      final plan = planCodexComposerSubmit(
        '/review',
        goalModeEnabled: false,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startReview);
      expect(plan.intent.value, isNull);
      expect(plan.normalizedText, '/review');
      expect(plan.handled, isTrue);
    });

    test('R1 /review <prompt> keeps startReview and prompt value', () {
      final plan = planCodexComposerSubmit(
        '/review 帮我审查 app/src/...',
        goalModeEnabled: false,
      );
      expect(plan.intent.kind, CodexSlashSubmitKind.startReview);
      expect(plan.intent.value, '帮我审查 app/src/...');
      expect(plan.plainText, '帮我审查 app/src/...');
      expect(plan.normalizedText, '/review 帮我审查 app/src/...');
      expect(plan.handled, isTrue);
    });
  });

  group('codexFastModeHint', () {
    test('F1 smooth on/off copy ZH/EN separates speed and billing', () {
      expect(
        kCodexFastModeHintOnZh,
        '已开启 Fast：响应更快（约 1.5×），计费约为标准的 1.5–2 倍。',
      );
      expect(
        kCodexFastModeHintOffZh,
        '已关闭 Fast：已恢复标准速度与标准计费。',
      );
      expect(
        kCodexFastModeHintOnEn,
        'Fast on: ~1.5× faster replies; billing ~1.5–2× Standard.',
      );
      expect(
        kCodexFastModeHintOffEn,
        'Fast off: standard speed and standard billing.',
      );

      expect(goalClearCommand, '/goal clear');
      expect(kCodexGoalClearCommand, '/goal clear');
      expect(codexFastModeHint(isEnglish: true), kCodexFastModeHintEn);
      expect(codexFastModeHint(isEnglish: false), kCodexFastModeHintZh);
      expect(codexFastModeHint(isEnglish: true), kCodexFastModeHintOnEn);
      expect(codexFastModeHint(isEnglish: false), kCodexFastModeHintOnZh);
      expect(codexFastModeHintOn(isEnglish: true), kCodexFastModeHintOnEn);
      expect(codexFastModeHintOff(isEnglish: false), kCodexFastModeHintOffZh);

      // On tips: speed + billing as separate clauses (not one shared multiplier).
      expect(kCodexFastModeHintOnEn, contains('1.5'));
      expect(kCodexFastModeHintOnEn.toLowerCase(), contains('billing'));
      expect(kCodexFastModeHintOnEn.toLowerCase(), contains('faster'));
      expect(kCodexFastModeHintOnEn, isNot(contains('priority')));
      expect(kCodexFastModeHintOnZh, contains('1.5'));
      expect(kCodexFastModeHintOnZh, contains('计费'));
      expect(kCodexFastModeHintOnZh, contains('响应更快'));
      expect(kCodexFastModeHintOnZh, isNot(contains('优先通道')));
      // Ambiguous old short form must be gone.
      expect(kCodexFastModeHintOnZh, isNot(contains('1.5× 速度；计费约')));
      expect(kCodexFastModeHintOnEn, isNot(contains('~1.5× speed; billing')));

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
      expect(kCodexFastModeHintOffEn.toLowerCase(), contains('standard billing'));
      expect(kCodexFastModeHintOffZh, contains('关闭'));
      expect(kCodexFastModeHintOffZh, contains('标准计费'));
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
        '已开启计划模式',
      );
      expect(
        codexSessionTipPlan(enabled: false, isEnglish: false),
        '已关闭计划模式',
      );
      expect(
        codexSessionTipPlan(enabled: true, isEnglish: true),
        'Plan mode on',
      );
      expect(
        codexSessionTipPlan(enabled: false, isEnglish: true),
        'Plan mode off',
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
