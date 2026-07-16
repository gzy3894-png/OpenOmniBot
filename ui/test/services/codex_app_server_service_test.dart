import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/codex_app_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('cn.com.omnimind.bot/CodexAppServer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('startTurn forwards codex permission payload', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.startTurn(
      conversationId: 42,
      threadId: 'thread-1',
      text: 'hello',
      approvalPolicy: 'never',
      approvalsReviewer: 'user',
      sandboxPolicy: const <String, dynamic>{'type': 'dangerFullAccess'},
      model: 'gpt-5-codex',
      effort: 'high',
      collaborationMode: 'plan',
    );

    expect(capturedCall?.method, 'turn/start');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['conversationId'], 42);
    expect(args['threadId'], 'thread-1');
    expect(args['text'], 'hello');
    expect(args['approvalPolicy'], 'never');
    expect(args['approvalsReviewer'], 'user');
    expect(args['sandboxPolicy'], const <String, dynamic>{
      'type': 'dangerFullAccess',
    });
    expect(args['model'], 'gpt-5-codex');
    expect(args['effort'], 'high');
    expect(args['collaborationMode'], 'plan');
  });

  test('startReview forwards codex review payload', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.startReview(
      conversationId: 42,
      threadId: 'thread-1',
      approvalPolicy: 'on-request',
      approvalsReviewer: 'guardian_subagent',
      model: 'gpt-5-codex',
      effort: 'xhigh',
      collaborationMode: 'plan',
    );

    expect(capturedCall?.method, 'review/start');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['conversationId'], 42);
    expect(args['threadId'], 'thread-1');
    expect(args['approvalPolicy'], 'on-request');
    expect(args['approvalsReviewer'], 'guardian_subagent');
    expect(args['target'], const <String, dynamic>{
      'type': 'uncommittedChanges',
    });
    expect(args['model'], 'gpt-5-codex');
    expect(args['effort'], 'xhigh');
    expect(args['collaborationMode'], 'plan');
  });

  test('B5 startReview forwards custom instructions target', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.startReview(
      conversationId: 7,
      threadId: 'thread-review',
      target: const <String, dynamic>{
        'type': 'custom',
        'instructions': '帮我审查 app/src/...',
      },
    );

    expect(capturedCall?.method, 'review/start');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['conversationId'], 7);
    expect(args['threadId'], 'thread-review');
    expect(args['target'], const <String, dynamic>{
      'type': 'custom',
      'instructions': '帮我审查 app/src/...',
    });
  });

  test('lists codex models, collaboration modes, and config', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.listModels();
    await CodexAppServerService.listCollaborationModes();
    await CodexAppServerService.readConfig();
    await CodexAppServerService.listLoadedThreads();

    expect(calls.map((call) => call.method), [
      'model/list',
      'collaborationMode/list',
      'config/read',
      'thread/loaded/list',
    ]);
    expect(calls.first.arguments, {'limit': 100});
  });

  test('updateThreadSettings forwards model and effort only', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.updateThreadSettings(
      threadId: ' thread-9 ',
      model: ' gpt-custom ',
      effort: ' high ',
    );

    expect(capturedCall?.method, 'thread/settings/update');
    expect(capturedCall?.arguments, {
      'threadId': 'thread-9',
      'model': 'gpt-custom',
      'effort': 'high',
    });
    // Omission: no serviceTier key when neither set nor clear.
    expect(
      (capturedCall?.arguments as Map).containsKey('serviceTier'),
      isFalse,
    );
  });

  test('B14 updateThreadSettings can clear serviceTier with JSON null',
      () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.updateThreadSettings(
      threadId: 'thread-fast-off',
      clearServiceTier: true,
    );

    expect(capturedCall?.method, 'thread/settings/update');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['threadId'], 'thread-fast-off');
    // Key present with null value (not omitted) so schema can clear.
    expect(args.containsKey('serviceTier'), isTrue);
    expect(args['serviceTier'], isNull);
  });

  test('B14 updateThreadSettings sets non-empty serviceTier string', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.updateThreadSettings(
      threadId: 'thread-fast-on',
      serviceTier: ' fast ',
    );

    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['serviceTier'], 'fast');
  });

  test('B14 clearServiceTier wins over serviceTier string', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.updateThreadSettings(
      threadId: 'thread-1',
      serviceTier: 'fast',
      clearServiceTier: true,
    );

    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args.containsKey('serviceTier'), isTrue);
    expect(args['serviceTier'], isNull);
  });

  test('B14 startTurn/startThread/startReview clearServiceTier sends null',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.startTurn(
      text: 'hi',
      clearServiceTier: true,
    );
    await CodexAppServerService.startThread(clearServiceTier: true);
    await CodexAppServerService.startReview(clearServiceTier: true);

    for (final call in calls) {
      final args = Map<String, dynamic>.from(
        (call.arguments as Map).cast<String, dynamic>(),
      );
      expect(args.containsKey('serviceTier'), isTrue, reason: call.method);
      expect(args['serviceTier'], isNull, reason: call.method);
    }
  });

  test('ignoreUserInput responds with empty answers payload', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.ignoreUserInput(requestId: 'request-1');

    expect(capturedCall?.method, 'respondToServerRequest');
    expect(capturedCall?.arguments, {
      'requestId': 'request-1',
      'response': {'answers': <String, dynamic>{}},
    });
  });

  test('readThread requests turns by default', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.readThread(threadId: 'thread-1');

    expect(capturedCall?.method, 'thread/read');
    expect(capturedCall?.arguments, {
      'threadId': 'thread-1',
      'includeTurns': true,
    });
  });

  test('reads and writes local codex config files', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{
        'baseUrl': 'https://example.com/v1',
        'model': 'gpt-5.5',
        'apiKey': 'key',
        'codexHome': '/root/.codex',
        'fastMode': false,
        'serviceTier': '',
      };
    });

    final read = await CodexAppServerService.readLocalConfig();
    final written = await CodexAppServerService.writeLocalConfig(
      baseUrl: ' https://example.com/v1 ',
      model: ' gpt-5.5 ',
      apiKey: ' key ',
    );

    expect(read.baseUrl, 'https://example.com/v1');
    expect(read.model, 'gpt-5.5');
    expect(read.apiKey, 'key');
    expect(read.isFastEnabled, isFalse);
    expect(written.codexHome, '/root/.codex');
    expect(calls.map((call) => call.method), [
      'config/local/read',
      'config/local/write',
    ]);
    // Omitting fastMode/serviceTier must not send them (preserve on native).
    expect(calls.last.arguments, <String, dynamic>{
      'baseUrl': 'https://example.com/v1',
      'model': 'gpt-5.5',
      'apiKey': 'key',
      'modelReasoningEffort': '',
      'defaultGoal': '',
      'remoteEnabled': false,
      'remoteBridgeUrl': '',
      'remoteBridgeToken': '',
      'remoteCwd': '',
    });
  });

  test('writeLocalConfig sends explicit fastMode false with empty serviceTier',
      () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, dynamic>{
        'baseUrl': 'https://example.com/v1',
        'model': 'gpt-5.5',
        'apiKey': 'key',
        'fastMode': false,
        'serviceTier': '',
      };
    });

    final written = await CodexAppServerService.writeLocalConfig(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5.5',
      apiKey: 'key',
      fastMode: false,
      serviceTier: '',
    );

    expect(written.isFastEnabled, isFalse);
    expect(captured?.method, 'config/local/write');
    final args = Map<String, dynamic>.from(captured!.arguments as Map);
    expect(args['fastMode'], isFalse);
    expect(args['serviceTier'], '');
  });

  test('writeLocalConfig sends fastMode true with serviceTier fast', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, dynamic>{
        'baseUrl': 'https://example.com/v1',
        'model': 'gpt-5.5',
        'apiKey': 'key',
        'fastMode': true,
        'serviceTier': 'fast',
      };
    });

    final written = await CodexAppServerService.writeLocalConfig(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5.5',
      apiKey: 'key',
      fastMode: true,
      serviceTier: 'fast',
    );

    expect(written.isFastEnabled, isTrue);
    expect(written.fastMode, isTrue);
    final args = Map<String, dynamic>.from(captured!.arguments as Map);
    expect(args['fastMode'], isTrue);
    expect(args['serviceTier'], 'fast');
  });

  test('CodexLocalConfig.isFastEnabled defaults off without explicit flags',
      () {
    final empty = CodexLocalConfig.fromMap(const {});
    // Missing key → null fastMode, not true; isFastEnabled stays false.
    expect(empty.fastMode, isNull);
    expect(empty.isFastEnabled, isFalse);

    final explicitFalse = CodexLocalConfig.fromMap(const {
      'fastMode': false,
      'serviceTier': '',
    });
    expect(explicitFalse.fastMode, isFalse);
    expect(explicitFalse.isFastEnabled, isFalse);

    final byMode = CodexLocalConfig.fromMap(const {'fastMode': true});
    expect(byMode.fastMode, isTrue);
    expect(byMode.isFastEnabled, isTrue);

    final byTier = CodexLocalConfig.fromMap(const {'serviceTier': 'priority'});
    expect(byTier.fastMode, isNull);
    expect(byTier.isFastEnabled, isTrue);

    final snake = CodexLocalConfig.fromMap(const {'fast_mode': true});
    expect(snake.fastMode, isTrue);
    expect(snake.isFastEnabled, isTrue);
  });

  test(
    'forwards remote filesystem operations without trimming content',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'config/remote/fs/read') {
          return <String, dynamic>{
            'ok': true,
            'path': '/repo/lib/main.dart',
            'name': 'main.dart',
            'previewKind': 'code',
            'mimeType': 'text/plain',
            'content': 'void main() {}',
          };
        }
        return <String, dynamic>{'ok': true};
      });

      final read = await CodexAppServerService.readRemoteFile(
        remoteBridgeUrl: ' ws://pc:17321/codex ',
        remoteBridgeToken: ' token ',
        remoteCwd: ' /repo ',
        path: ' /repo/lib/main.dart ',
      );
      await CodexAppServerService.writeRemoteFile(
        path: '/repo/lib/main.dart',
        content: '  keep whitespace\n',
      );
      await CodexAppServerService.deleteRemotePath(
        path: '/repo/tmp',
        recursive: true,
      );
      await CodexAppServerService.moveRemotePath(
        path: '/repo/a.dart',
        destinationPath: '/repo/b.dart',
      );

      expect(read.content, 'void main() {}');
      expect(calls.map((call) => call.method), [
        'config/remote/fs/read',
        'config/remote/fs/write',
        'config/remote/fs/delete',
        'config/remote/fs/move',
      ]);
      expect(calls[0].arguments, <String, dynamic>{
        'remoteBridgeUrl': 'ws://pc:17321/codex',
        'remoteBridgeToken': 'token',
        'remoteCwd': '/repo',
        'path': '/repo/lib/main.dart',
      });
      expect((calls[1].arguments as Map)['content'], '  keep whitespace\n');
      expect((calls[2].arguments as Map)['recursive'], true);
      expect((calls[3].arguments as Map)['destinationPath'], '/repo/b.dart');
    },
  );
}
