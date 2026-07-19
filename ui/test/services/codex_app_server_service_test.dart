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

  test('B38 startThread forwards permission triad', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true, 'threadId': 't1'};
    });

    await CodexAppServerService.startThread(
      conversationId: 7,
      cwd: '/workspace',
      approvalPolicy: 'on-request',
      approvalsReviewer: 'auto_review',
      sandboxPolicy: <String, dynamic>{
        'type': 'workspaceWrite',
        'writableRoots': <String>['/workspace'],
        'networkAccess': true,
      },
    );

    expect(capturedCall?.method, 'thread/start');
    final args = Map<String, dynamic>.from(
      (capturedCall?.arguments as Map).cast<String, dynamic>(),
    );
    expect(args['conversationId'], 7);
    expect(args['cwd'], '/workspace');
    expect(args['approvalPolicy'], 'on-request');
    expect(args['approvalsReviewer'], 'auto_review');
    expect(args['sandboxPolicy'], <String, dynamic>{
      'type': 'workspaceWrite',
      'writableRoots': <String>['/workspace'],
      'networkAccess': true,
    });
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

  test('goal RPCs require a live threadId before invoking native', () {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });

    expect(
      () => CodexAppServerService.getThreadGoal(conversationId: 7),
      throwsStateError,
    );
    expect(
      () => CodexAppServerService.setThreadGoal(
        conversationId: 7,
        objective: 'ship safely',
      ),
      throwsStateError,
    );
    expect(
      () => CodexAppServerService.clearThreadGoal(conversationId: 7),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });

  test('goal RPC trims and forwards its live threadId', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.getThreadGoal(
      threadId: ' thread-goal ',
      conversationId: 7,
    );

    expect(capturedCall?.method, 'thread/goal/get');
    expect(capturedCall?.arguments, {
      'threadId': 'thread-goal',
      'conversationId': 7,
    });
  });

  test('connect reports bounded channel-unavailable failure', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      attempts += 1;
      throw MissingPluginException('engine is reconfiguring');
    });

    await expectLater(
      CodexAppServerService.connect(),
      throwsA(
        isA<CodexChannelUnavailableException>()
            .having((error) => error.method, 'method', 'connect')
            .having((error) => error.attempts, 'attempts', 6),
      ),
    );
    expect(attempts, 6);
  });

  test('connect retries a detached native channel and recovers', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      attempts += 1;
      if (attempts < 3) {
        throw PlatformException(
          code: 'CODEX_CHANNEL_DETACHED',
          message: 'engine is reconfiguring',
        );
      }
      return <String, dynamic>{'connected': true, 'ready': true};
    });

    final status = await CodexAppServerService.connect();

    expect(attempts, 3);
    expect(status.connected, isTrue);
  });

  test('model switch sends clamped effort atomically, never old effort',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });

    const oldEffort = 'xhigh';
    await CodexAppServerService.updateThreadSettings(
      threadId: ' thread-9 ',
      model: ' gpt-custom ',
      effort: ' high ',
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'thread/settings/update');
    expect(calls.single.arguments, {
      'threadId': 'thread-9',
      'model': 'gpt-custom',
      'effort': 'high',
    });
    expect(
      (calls.single.arguments as Map)['effort'],
      isNot(oldEffort),
    );
    // Omission: no serviceTier key when neither set nor clear.
    expect(
      (calls.single.arguments as Map).containsKey('serviceTier'),
      isFalse,
    );
  });

  test('HTTP-only model updates and turns omit cleared effort', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.updateThreadSettings(
      threadId: 'thread-http-only',
      model: 'provider-only-model',
      effort: null,
    );
    await CodexAppServerService.startTurn(
      threadId: 'thread-http-only',
      text: 'hello',
      model: 'provider-only-model',
      effort: null,
    );

    for (final call in calls) {
      final args = Map<String, dynamic>.from(
        (call.arguments as Map).cast<String, dynamic>(),
      );
      expect(args['model'], 'provider-only-model', reason: call.method);
      expect(args.containsKey('effort'), isFalse, reason: call.method);
    }
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

    await CodexAppServerService.ignoreUserInput(
      requestId: 'request-1',
      sessionGeneration: 12,
      serverRequestMethod: 'item/tool/requestUserInput',
    );

    expect(capturedCall?.method, 'respondToServerRequest');
    expect(capturedCall?.arguments, {
      'requestId': 'request-1',
      'sessionGeneration': 12,
      'serverRequestMethod': 'item/tool/requestUserInput',
      'response': {'answers': <String, dynamic>{}},
    });
  });

  test('respondToUserInput forwards generation and request method', () async {
    MethodCall? capturedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await CodexAppServerService.respondToUserInput(
      requestId: 0,
      sessionGeneration: 13,
      serverRequestMethod: 'item/tool/requestUserInput',
      questionId: 'mode',
      answers: const <String>['Plan'],
    );

    expect(capturedCall?.arguments, {
      'requestId': 0,
      'sessionGeneration': 13,
      'serverRequestMethod': 'item/tool/requestUserInput',
      'response': {
        'answers': {
          'mode': {
            'answers': <String>['Plan'],
          },
        },
      },
    });
  });

  test('builds typed command and file approval responses', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{
        'ok': true,
        'resolved': false,
        'actionResult': 'response_sent',
      };
    });

    final command = CodexApprovalRequestPayload.fromCardData(
      <String, dynamic>{
        'requestId': 0,
        'sessionGeneration': 20,
        'serverRequestMethod': 'item/commandExecution/requestApproval',
        'rawParamsJson': '{"command":"rm tmp.txt"}',
      },
    );
    final fileChange = CodexApprovalRequestPayload.fromCardData(
      <String, dynamic>{
        'requestId': '0',
        'sessionGeneration': 20,
        'serverRequestMethod': 'item/fileChange/requestApproval',
        'rawParamsJson': '{"reason":"write outside workspace"}',
      },
    );

    expect(
      command,
      isA<CodexCommandExecutionApprovalRequestPayload>(),
    );
    expect(fileChange, isA<CodexFileChangeApprovalRequestPayload>());
    await CodexAppServerService.respondToApproval(
      request: command,
      accepted: true,
    );
    await CodexAppServerService.respondToApproval(
      request: fileChange,
      accepted: false,
    );

    expect(calls[0].arguments, {
      'requestId': 0,
      'sessionGeneration': 20,
      'serverRequestMethod': 'item/commandExecution/requestApproval',
      'response': {'decision': 'accept'},
    });
    expect(calls[1].arguments, {
      'requestId': '0',
      'sessionGeneration': 20,
      'serverRequestMethod': 'item/fileChange/requestApproval',
      'response': {'decision': 'decline'},
    });
  });

  test('permissions approval returns granted profile or empty denial', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{'ok': true};
    });
    const permissions = <String, dynamic>{
      'network': <String, dynamic>{'enabled': true},
      'fileSystem': <String, dynamic>{
        'write': <String>['/workspace'],
      },
    };
    final request = CodexApprovalRequestPayload.fromCardData(
      <String, dynamic>{
        'requestId': 7,
        'sessionGeneration': 21,
        'serverRequestMethod': 'item/permissions/requestApproval',
        'requestParams': <String, dynamic>{
          'permissions': permissions,
        },
      },
    );

    expect(request, isA<CodexPermissionsApprovalRequestPayload>());
    await CodexAppServerService.respondToApproval(
      request: request,
      accepted: true,
    );
    await CodexAppServerService.respondToApproval(
      request: request,
      accepted: false,
    );

    expect((calls[0].arguments as Map)['response'], {
      'permissions': permissions,
      'scope': 'turn',
    });
    expect((calls[1].arguments as Map)['response'], {
      'permissions': <String, dynamic>{},
      'scope': 'turn',
    });
  });

  test('approval payload rejects missing generation before native call', () {
    expect(
      () => CodexApprovalRequestPayload.fromCardData(
        <String, dynamic>{
          'requestId': 1,
          'serverRequestMethod': 'item/commandExecution/requestApproval',
          'rawParamsJson': '{}',
        },
      ),
      throwsFormatException,
    );
  });

  test('approval payload rejects zero generation before native call', () {
    expect(
      () => CodexApprovalRequestPayload.fromCardData(
        <String, dynamic>{
          'requestId': 1,
          'sessionGeneration': 0,
          'serverRequestMethod': 'item/commandExecution/requestApproval',
          'rawParamsJson': '{}',
        },
      ),
      throwsFormatException,
    );
  });

  test('server response methods reject zero generation before native call', () {
    expect(
      () => CodexAppServerService.respondToUserInput(
        requestId: 1,
        sessionGeneration: 0,
        serverRequestMethod: 'item/tool/requestUserInput',
        questionId: 'mode',
        answers: const <String>['Plan'],
      ),
      throwsArgumentError,
    );
  });

  test('event retry policy uses capped exponential backoff', () {
    expect(CodexAppServerService.eventRetryAttemptForTesting, 0);
    expect(CodexAppServerService.hasEventSubscriptionForTesting, isFalse);
    expect(
      CodexAppServerService.eventRetryDelayForAttempt(1),
      const Duration(milliseconds: 250),
    );
    expect(
      CodexAppServerService.eventRetryDelayForAttempt(4),
      const Duration(seconds: 2),
    );
    expect(
      CodexAppServerService.eventRetryDelayForAttempt(99),
      const Duration(seconds: 8),
    );
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

  test('CodexLocalConfig.contextTokenThreshold parses aliases and null default',
      () {
    expect(CodexLocalConfig.fromMap(const {}).contextTokenThreshold, isNull);
    expect(
      CodexLocalConfig.fromMap(const {
        'contextTokenThreshold': 128000,
      }).contextTokenThreshold,
      128000,
    );
    expect(
      CodexLocalConfig.fromMap(const {
        'omnimind_context_token_threshold': 64000,
      }).contextTokenThreshold,
      64000,
    );
    expect(
      CodexLocalConfig.fromMap(const {
        'context_token_threshold': 32000,
      }).contextTokenThreshold,
      32000,
    );
  });

  test('writeLocalConfig sends contextTokenThreshold only when provided',
      () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return <String, dynamic>{
        'baseUrl': 'https://example.com/v1',
        'model': 'gpt-5.5',
        'apiKey': 'key',
        'contextTokenThreshold': 128000,
      };
    });

    final omitted = await CodexAppServerService.writeLocalConfig(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5.5',
      apiKey: 'key',
    );
    final omitArgs = Map<String, dynamic>.from(captured!.arguments as Map);
    expect(omitArgs.containsKey('contextTokenThreshold'), isFalse);
    expect(omitted.contextTokenThreshold, 128000);

    final written = await CodexAppServerService.writeLocalConfig(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5.5',
      apiKey: 'key',
      contextTokenThreshold: 128000,
    );
    final args = Map<String, dynamic>.from(captured!.arguments as Map);
    expect(args['contextTokenThreshold'], 128000);
    expect(written.contextTokenThreshold, 128000);
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
