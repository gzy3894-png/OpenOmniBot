import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/utils/codex_slash_commands.dart';

void main() {
  test('routes codex model command intents', () {
    expect(
      resolveCodexSlashSubmitIntent('/model').kind,
      CodexSlashSubmitKind.openModelPicker,
    );

    final intent = resolveCodexSlashSubmitIntent('/model gpt-5-codex');
    expect(intent.kind, CodexSlashSubmitKind.selectModel);
    expect(intent.value, 'gpt-5-codex');
  });

  test('routes codex review init and plan command intents', () {
    expect(
      resolveCodexSlashSubmitIntent('/review').kind,
      CodexSlashSubmitKind.startReview,
    );
    // R1: `/review <prompt>` must not fall through as unsupported.
    final reviewPrompted = resolveCodexSlashSubmitIntent(
      '/review 帮我审查 app/src/...',
    );
    expect(reviewPrompted.kind, CodexSlashSubmitKind.startReview);
    expect(reviewPrompted.value, '帮我审查 app/src/...');
    expect(
      resolveCodexSlashSubmitIntent('/init').kind,
      CodexSlashSubmitKind.startInit,
    );
    expect(
      resolveCodexSlashSubmitIntent('/plan').kind,
      CodexSlashSubmitKind.togglePlan,
    );

    final planIntent = resolveCodexSlashSubmitIntent('/plan inspect the diff');
    expect(planIntent.kind, CodexSlashSubmitKind.startPlan);
    expect(planIntent.value, 'inspect the diff');

    expect(
      resolveCodexSlashSubmitIntent('/chat').kind,
      CodexSlashSubmitKind.unsupported,
    );
    expect(
      resolveCodexSlashSubmitIntent('/normal').kind,
      CodexSlashSubmitKind.unsupported,
    );
  });

  test('routes compact status diff stop new resume and goal intents', () {
    expect(
      resolveCodexSlashSubmitIntent('/compact').kind,
      CodexSlashSubmitKind.startCompact,
    );
    // B34: Fast / auto-compact are exclusive from startCompact.
    expect(
      resolveCodexSlashSubmitIntent('/fast').kind,
      CodexSlashSubmitKind.toggleFast,
    );
    expect(
      resolveCodexSlashSubmitIntent('/auto-compact').kind,
      CodexSlashSubmitKind.toggleAutoCompact,
    );
    expect(
      resolveCodexSlashSubmitIntent('/auto-compaction').kind,
      CodexSlashSubmitKind.toggleAutoCompact,
    );
    expect(
      resolveCodexSlashSubmitIntent('/status').kind,
      CodexSlashSubmitKind.showStatus,
    );
    expect(
      resolveCodexSlashSubmitIntent('/diff').kind,
      CodexSlashSubmitKind.showDiff,
    );
    expect(
      resolveCodexSlashSubmitIntent('/stop').kind,
      CodexSlashSubmitKind.stopTurn,
    );
    expect(
      resolveCodexSlashSubmitIntent('/clean').kind,
      CodexSlashSubmitKind.stopTurn,
    );
    expect(
      resolveCodexSlashSubmitIntent('/new').kind,
      CodexSlashSubmitKind.startNew,
    );
    expect(
      resolveCodexSlashSubmitIntent('/clear').kind,
      CodexSlashSubmitKind.startNew,
    );

    final resumeBare = resolveCodexSlashSubmitIntent('/resume');
    expect(resumeBare.kind, CodexSlashSubmitKind.resumeThread);
    expect(resumeBare.value, isNull);

    final resumeWithId = resolveCodexSlashSubmitIntent('/resume thread-123');
    expect(resumeWithId.kind, CodexSlashSubmitKind.resumeThread);
    expect(resumeWithId.value, 'thread-123');

    expect(
      resolveCodexSlashSubmitIntent('/goal').kind,
      CodexSlashSubmitKind.showGoal,
    );
    expect(
      resolveCodexSlashSubmitIntent('/goal clear').kind,
      CodexSlashSubmitKind.clearGoal,
    );
    expect(
      resolveCodexSlashSubmitIntent('/goal --clear').kind,
      CodexSlashSubmitKind.clearGoal,
    );

    final setGoal = resolveCodexSlashSubmitIntent('/goal ship the slash UX');
    expect(setGoal.kind, CodexSlashSubmitKind.setGoal);
    expect(setGoal.value, 'ship the slash UX');
  });

  test('rejects agent-only slash commands in codex mode', () {
    expect(
      resolveCodexSlashSubmitIntent('/effort high').kind,
      CodexSlashSubmitKind.unsupported,
    );
    expect(
      resolveCodexSlashSubmitIntent('/openclaw http://example.com').kind,
      CodexSlashSubmitKind.unsupported,
    );
  });

  test('routes /skill command intents', () {
    final bare = resolveCodexSlashSubmitIntent('/skill');
    expect(bare.kind, CodexSlashSubmitKind.startSkill);
    expect(bare.value, '');

    final withArgs = resolveCodexSlashSubmitIntent('/skill review-pr fix tests');
    expect(withArgs.kind, CodexSlashSubmitKind.startSkill);
    expect(withArgs.value, 'review-pr fix tests');
  });
}
