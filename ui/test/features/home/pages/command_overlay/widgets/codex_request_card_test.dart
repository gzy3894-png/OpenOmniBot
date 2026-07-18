import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/codex_request_card.dart';
import 'package:ui/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const requestIdentity =
      '7.item/tool/requestUserInput.string:request-1.request-1-card.mode.1000';
  const requestStorageKey = 'codex_request_response.$requestIdentity';
  const codexChannel = MethodChannel('cn.com.omnimind.bot/CodexAppServer');
  const assistCoreChannel = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(assistCoreChannel, (call) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, null);
    messenger.setMockMethodCallHandler(assistCoreChannel, null);
  });

  testWidgets('renders requestUserInput options and submits selection', (
    tester,
  ) async {
    MethodCall? submittedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      submittedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: _requestCardData())),
      ),
    );

    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('No, tell Codex how to adjust'), findsOneWidget);
    expect(find.text('ESC'), findsNothing);

    await tester.tap(find.text('Chat'));
    await tester.pump();
    await tester.tap(find.text('Submit ↵'));
    await tester.pumpAndSettle();

    expect(submittedCall?.method, 'respondToServerRequest');
    expect(submittedCall?.arguments, containsPair('requestId', 'request-1'));
    final arguments = Map<String, dynamic>.from(
      submittedCall!.arguments as Map,
    );
    final response = Map<String, dynamic>.from(arguments['response'] as Map);
    final answers = Map<String, dynamic>.from(response['answers'] as Map);
    final mode = Map<String, dynamic>.from(answers['mode'] as Map);
    expect(mode['answers'], <String>['Chat']);
    expect(arguments['sessionGeneration'], 7);
    expect(
      arguments['serverRequestMethod'],
      'item/tool/requestUserInput',
    );
    expect(find.text('Response sent: Chat'), findsOneWidget);

    final stored = jsonDecode(StorageService.getString(requestStorageKey)!);
    expect(stored, containsPair('identity', requestIdentity));
  });

  testWidgets('ignore submits empty request user input answers', (
    tester,
  ) async {
    MethodCall? submittedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      submittedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: _requestCardData())),
      ),
    );

    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    final arguments = Map<String, dynamic>.from(
      submittedCall!.arguments as Map,
    );
    expect(arguments['requestId'], 'request-1');
    expect(arguments['sessionGeneration'], 7);
    expect(
      arguments['serverRequestMethod'],
      'item/tool/requestUserInput',
    );
    expect(arguments['response'], {'answers': <String, dynamic>{}});
    expect(find.text('Response sent: ignored'), findsOneWidget);
  });

  testWidgets('pending request ignores legacy submitted cache', (tester) async {
    await StorageService.setString(
      requestStorageKey,
      jsonEncode(<String, dynamic>{
        'status': 'submitted',
        'answers': <String>['Chat'],
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: _requestCardData())),
      ),
    );

    expect(find.text('submitted: Chat'), findsNothing);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('No, tell Codex how to adjust'), findsOneWidget);
  });

  testWidgets('pending request restores exact response-sent cache after refresh', (
    tester,
  ) async {
    await StorageService.setString(
      requestStorageKey,
      jsonEncode(<String, dynamic>{
        'identity': requestIdentity,
        'status': 'response_sent',
        'answers': <String>['Chat'],
        'submittedAction': 'submitted',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: _requestCardData())),
      ),
    );

    expect(find.text('Response sent: Chat'), findsOneWidget);
    expect(find.text('Plan'), findsNothing);
    expect(find.text('No, tell Codex how to adjust'), findsNothing);
  });

  testWidgets('does not render duplicate title and detail question text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: _requestCardData(detail: 'Choose mode'),
          ),
        ),
      ),
    );

    expect(find.text('Choose mode'), findsOneWidget);
  });

  testWidgets('custom answer input uses provider field styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: CodexRequestCard(cardData: _requestCardData()),
          ),
        ),
      ),
    );

    final optionRow = find.byKey(const ValueKey('codex-request-option-row-1'));
    final customInput = find.byKey(
      const ValueKey('codex-request-custom-answer-input'),
    );
    final textField = tester.widget<TextField>(find.byType(TextField));

    expect(optionRow, findsOneWidget);
    expect(customInput, findsOneWidget);
    expect(textField.minLines, 1);
    expect(textField.maxLines, 1);
    expect(textField.textInputAction, TextInputAction.done);
    expect(textField.decoration?.labelText, 'No, tell Codex how to adjust');
    expect(textField.decoration?.hintText, 'Describe the adjustment');
    expect(textField.style?.fontSize, 13);
    expect(
      tester.getTopLeft(customInput).dx,
      closeTo(tester.getTopLeft(optionRow).dx, 0.1),
    );
    expect(
      tester.getSize(customInput).width,
      closeTo(tester.getSize(optionRow).width, 0.1),
    );
  });

  testWidgets(
    'custom answer input keeps keyboard clearance in scroll padding',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                viewInsets: EdgeInsets.only(bottom: 320),
              ),
              child: CodexRequestCard(cardData: _requestCardData()),
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));

      expect(textField.scrollPadding.top, 24);
      expect(textField.scrollPadding.bottom, 416);
    },
  );

  testWidgets('submits custom adjustment text when entered', (tester) async {
    MethodCall? submittedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      submittedCall = call;
      return <String, dynamic>{'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: _requestCardData())),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'Please make the options wider',
    );
    await tester.pump();
    await tester.tap(find.text('Submit ↵'));
    await tester.pumpAndSettle();

    final arguments = Map<String, dynamic>.from(
      submittedCall!.arguments as Map,
    );
    final response = Map<String, dynamic>.from(arguments['response'] as Map);
    final answers = Map<String, dynamic>.from(response['answers'] as Map);
    final mode = Map<String, dynamic>.from(answers['mode'] as Map);
    expect(mode['answers'], <String>['Please make the options wider']);
  });

  testWidgets('submits all three approval schemas with lifecycle identity', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      calls.add(call);
      return <String, dynamic>{
        'ok': true,
        'resolved': false,
        'actionResult': 'response_sent',
      };
    });
    final cases = <(String, String, Map<String, dynamic>)>[
      (
        'item/commandExecution/requestApproval',
        'Accept',
        <String, dynamic>{'command': 'rm tmp.txt'},
      ),
      (
        'item/fileChange/requestApproval',
        'Decline',
        <String, dynamic>{'reason': 'write outside workspace'},
      ),
      (
        'item/permissions/requestApproval',
        'Accept',
        <String, dynamic>{
          'permissions': <String, dynamic>{
            'fileSystem': <String, dynamic>{
              'write': <String>['/workspace'],
            },
          },
        },
      ),
    ];

    for (var index = 0; index < cases.length; index += 1) {
      final entry = cases[index];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CodexRequestCard(
              cardData: _approvalCardData(
                requestId: index,
                method: entry.$1,
                params: entry.$3,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(entry.$2));
      await tester.pumpAndSettle();
    }

    expect(calls, hasLength(3));
    expect((calls[0].arguments as Map)['response'], {
      'decision': 'accept',
    });
    expect((calls[1].arguments as Map)['response'], {
      'decision': 'decline',
    });
    expect((calls[2].arguments as Map)['response'], {
      'permissions': <String, dynamic>{
        'fileSystem': <String, dynamic>{
          'write': <String>['/workspace'],
        },
      },
      'scope': 'turn',
    });
    for (final call in calls) {
      expect((call.arguments as Map)['sessionGeneration'], 9);
      expect(
        (call.arguments as Map)['serverRequestMethod'],
        isNotEmpty,
      );
    }
  });

  testWidgets('prevents duplicate approval response after send', (
    tester,
  ) async {
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      callCount += 1;
      return <String, dynamic>{'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: _approvalCardData(
              requestId: 1,
              method: 'item/commandExecution/requestApproval',
              params: const <String, dynamic>{'command': 'pwd'},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Accept'));
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(find.text('Response sent: accepted'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('transient approval failure stays pending and retryable', (
    tester,
  ) async {
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      callCount += 1;
      if (callCount == 1) {
        throw PlatformException(
          code: 'CODEX_SERVER_RESPONSE_WRITE_FAILED',
          message: 'Temporary write failure',
        );
      }
      return <String, dynamic>{'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: _approvalCardData(
              requestId: 2,
              method: 'item/commandExecution/requestApproval',
              params: const <String, dynamic>{'command': 'pwd'},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('codex-request-submit-error')),
      findsOneWidget,
    );
    expect(find.text('Accept'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(callCount, 2);
    expect(find.text('Response sent: accepted'), findsOneWidget);
  });

  testWidgets('stale or legacy approval is invalidated without retry', (
    tester,
  ) async {
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      callCount += 1;
      throw PlatformException(
        code: 'CODEX_STALE_SERVER_REQUEST',
        message: 'Session generation does not match',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: _approvalCardData(
              requestId: 3,
              method: 'item/commandExecution/requestApproval',
              params: const <String, dynamic>{'command': 'pwd'},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(callCount, 1);
    expect(find.text('Expired — retry the action'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);

    final legacy = _approvalCardData(
      requestId: 4,
      method: 'item/commandExecution/requestApproval',
      params: const <String, dynamic>{'command': 'pwd'},
    )..remove('sessionGeneration');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: legacy)),
      ),
    );
    await tester.pump();
    expect(find.text('Expired — retry the action'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(callCount, 1);
  });

  testWidgets('already responded waits for resolved without another retry', (
    tester,
  ) async {
    var callCount = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(codexChannel, (call) async {
      callCount += 1;
      throw PlatformException(
        code: 'CODEX_SERVER_REQUEST_ALREADY_RESPONDED',
        message: 'Another engine responded first',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: _approvalCardData(
              requestId: 6,
              method: 'item/commandExecution/requestApproval',
              params: const <String, dynamic>{'command': 'pwd'},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(
      find.text('Handled in another view — waiting for server'),
      findsOneWidget,
    );
    expect(find.textContaining('accepted'), findsNothing);
    expect(find.textContaining('declined'), findsNothing);
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Decline'), findsNothing);
  });

  testWidgets('server resolved status overrides local response sent state', (
    tester,
  ) async {
    final responseSent = _approvalCardData(
      requestId: 5,
      method: 'item/commandExecution/requestApproval',
      params: const <String, dynamic>{'command': 'pwd'},
    )
      ..['status'] = 'response_sent'
      ..['submittedAction'] = 'accepted';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodexRequestCard(cardData: responseSent)),
      ),
    );
    expect(find.text('Response sent: accepted'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodexRequestCard(
            cardData: <String, dynamic>{
              ...responseSent,
              'status': 'resolved',
              'resolved': true,
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Resolved'), findsOneWidget);
    expect(find.text('Response sent: accepted'), findsNothing);
  });

  testWidgets('fills the available message width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: CodexRequestCard(cardData: _requestCardData()),
            ),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('codex-request-card-surface'));
    expect(surface, findsOneWidget);
    expect(tester.getSize(surface).width, closeTo(360, 0.1));
  });
}

Map<String, dynamic> _requestCardData({String detail = 'Pick one'}) {
  return <String, dynamic>{
    'type': 'codex_request',
    'requestId': 'request-1',
    'sessionGeneration': 7,
    'serverRequestMethod': 'item/tool/requestUserInput',
    'cardId': 'request-1-card',
    'requestKind': 'user_input',
    'title': 'Choose mode',
    'detail': detail,
    'questionId': 'mode',
    'status': 'pending',
    'startTime': 1000,
    'rawParamsJson': jsonEncode({
      'questions': [
        {
          'id': 'mode',
          'question': 'Choose mode',
          'options': [
            {'label': 'Plan', 'description': 'Plan first'},
            {'label': 'Chat', 'description': 'Answer directly'},
          ],
        },
      ],
    }),
  };
}

Map<String, dynamic> _approvalCardData({
  required Object requestId,
  required String method,
  required Map<String, dynamic> params,
}) {
  return <String, dynamic>{
    'type': 'codex_request',
    'requestId': requestId,
    'sessionGeneration': 9,
    'serverRequestMethod': method,
    'cardId': 'approval-$requestId',
    'requestKind': 'approval',
    'title': 'Codex approval',
    'detail': 'Review this action',
    'status': 'pending',
    'startTime': 2000,
    'rawParamsJson': jsonEncode(params),
  };
}
