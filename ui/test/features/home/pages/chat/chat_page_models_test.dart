import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_app_server_service.dart';

void main() {
  group('Codex model effort resolution', () {
    test('authoritative empty effort catalog clears an old override', () {
      expect(
        resolveCodexModelEffortForTesting(
          preferred: 'high',
          supportedEfforts: const <String>[],
          catalogAuthoritative: true,
        ),
        isNull,
      );
    });

    test('model switch clamps old effort to the target model default', () {
      expect(
        resolveCodexModelEffortForTesting(
          preferred: 'xhigh',
          supportedEfforts: const <String>['low', 'high'],
          modelDefault: 'high',
          catalogAuthoritative: true,
        ),
        'high',
      );
    });
  });

  group('Codex authoritative model catalog', () {
    test('successful empty catalog rejects app-server ghost models', () {
      expect(
        isCodexModelSelectableFromCatalog(
          modelId: 'ghost-model',
          modelOptions: const <String>[],
          catalogAuthoritative: true,
        ),
        isFalse,
      );
    });

    test('pre-catalog server state remains a cautious cold-start fallback', () {
      expect(
        isCodexModelSelectableFromCatalog(
          modelId: 'server-model',
          modelOptions: const <String>[],
          catalogAuthoritative: false,
        ),
        isTrue,
      );
    });
  });

  group('Codex model catalog ready-load gating', () {
    test('authoritative empty or no-effort catalog is not fetched again', () {
      expect(
        shouldLoadCodexModelCatalogWhenReady(
          isLoading: false,
          appliedProviderIdentity: 'local:/codex|local:https://provider#1',
          loadError: null,
        ),
        isFalse,
      );
    });

    test('never-applied and failed catalogs remain retryable', () {
      expect(
        shouldLoadCodexModelCatalogWhenReady(
          isLoading: false,
          appliedProviderIdentity: null,
          loadError: null,
        ),
        isTrue,
      );
      expect(
        shouldLoadCodexModelCatalogWhenReady(
          isLoading: false,
          appliedProviderIdentity: 'remote:wss://pc|remote',
          loadError: 'temporary failure',
        ),
        isTrue,
      );
    });

    test('in-flight catalog request is never duplicated', () {
      expect(
        shouldLoadCodexModelCatalogWhenReady(
          isLoading: true,
          appliedProviderIdentity: null,
          loadError: 'stale error',
        ),
        isFalse,
      );
    });
  });

  group('Codex deferred server-request lifecycle events', () {
    Map<String, dynamic> pending({
      required Object requestId,
      int generation = 41,
      String? requestKey,
      String method = 'item/commandExecution/requestApproval',
      bool includeServerRequestMethod = true,
      String? threadId,
    }) {
      return <String, dynamic>{
        'method': method,
        'sessionGeneration': generation,
        'requestId': requestId,
        if (includeServerRequestMethod) 'serverRequestMethod': method,
        if (requestKey != null) 'serverRequestKey': requestKey,
        if (threadId != null) 'threadId': threadId,
      };
    }

    Map<String, dynamic> terminal({
      required Object requestId,
      int generation = 41,
      String? requestKey,
      String method = 'serverRequest/resolved',
      String? serverRequestMethod =
          'item/commandExecution/requestApproval',
    }) {
      return <String, dynamic>{
        'method': method,
        'sessionGeneration': generation,
        'requestId': requestId,
        if (serverRequestMethod != null)
          'serverRequestMethod': serverRequestMethod,
        if (requestKey != null) 'serverRequestKey': requestKey,
      };
    }

    test('actual route decision defers locally then maps remote thread once', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      final replay = pending(
        requestId: 7,
        requestKey: '41/number:7',
        threadId: 'remote-thread-7',
      );
      expect(buffer.add(replay), isTrue);

      var status = CodexStatus.disconnected;
      final routedConversationIds = <int>[];
      bool tryRoute(Map<String, dynamic> event) {
        final decision = decideCodexAppServerEventRoute(
          status: status,
          event: event,
          currentConversationId: null,
        );
        final conversationId = decision.resolve();
        if (conversationId == null) {
          expect(decision.shouldDefer, isTrue);
          return false;
        }
        routedConversationIds.add(conversationId);
        return true;
      }

      expect(buffer.drain(tryRoute), 0);
      expect(buffer.length, 1);
      status = const CodexStatus(
        connected: true,
        ready: true,
        runtime: 'remote',
        remoteEnabled: true,
      );
      final remoteDecision = decideCodexAppServerEventRoute(
        status: status,
        event: replay,
        currentConversationId: null,
      );
      expect(remoteDecision.remoteCodex, isTrue);
      expect(remoteDecision.eventThreadId, 'remote-thread-7');
      expect(remoteDecision.mappedRemoteConversationId, isNotNull);
      expect(remoteDecision.resolve(), remoteDecision.mappedRemoteConversationId);

      expect(buffer.drain(tryRoute), 1);
      expect(buffer.drain(tryRoute), 0);
      expect(
        routedConversationIds,
        <int>[remoteDecision.mappedRemoteConversationId!],
      );
    });

    test('a blocked request identity does not block another identity', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      expect(buffer.add(pending(requestId: 'A')), isTrue);
      expect(buffer.add(pending(requestId: 'B')), isTrue);

      final attempted = <Object>[];
      expect(
        buffer.drain((event) {
          final requestId = event['requestId']!;
          attempted.add(requestId);
          return requestId == 'B';
        }),
        1,
      );
      expect(attempted, <Object>['A', 'B', 'A']);
      expect(buffer.length, 1);

      final routed = <Object>[];
      expect(
        buffer.drain((event) {
          routed.add(event['requestId']!);
          return true;
        }),
        1,
      );
      expect(routed, <Object>['A']);
    });

    test('terminal never overtakes pending for the same identity', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      expect(buffer.add(pending(requestId: 9)), isTrue);
      expect(buffer.add(terminal(requestId: 9)), isTrue);

      final attempted = <String>[];
      expect(
        buffer.drain((event) {
          final method = event['method']! as String;
          attempted.add(method);
          return method == 'serverRequest/resolved';
        }),
        0,
      );
      expect(attempted, <String>['item/commandExecution/requestApproval']);
      expect(buffer.length, 2);

      final routed = <String>[];
      expect(
        buffer.drain((event) {
          routed.add(event['method']! as String);
          return true;
        }),
        2,
      );
      expect(
        routed,
        <String>[
          'item/commandExecution/requestApproval',
          'serverRequest/resolved',
        ],
      );
    });

    test('method metadata is excluded from identity and phase dedup', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      expect(
        buffer.add(
          pending(
            requestId: 5,
            requestKey: '41/number:5',
            includeServerRequestMethod: false,
          ),
        ),
        isTrue,
      );
      expect(
        buffer.add(
          pending(
            requestId: 5,
            requestKey: '41/number:5',
            method: 'item/fileChange/requestApproval',
          ),
        ),
        isTrue,
      );
      expect(buffer.length, 1);

      final routed = <String>[];
      expect(
        buffer.drain((event) {
          routed.add(event['method']! as String);
          return true;
        }),
        1,
      );
      expect(routed, <String>['item/fileChange/requestApproval']);
    });

    test('reentrant same-phase add is not removed with routed predecessor', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      final first = <String, dynamic>{
        ...pending(requestId: 6, requestKey: '41/number:6'),
        'revision': 1,
      };
      expect(buffer.add(first), isTrue);

      final revisions = <int>[];
      expect(
        buffer.drain((event) {
          revisions.add(event['revision']! as int);
          if (event['revision'] == 1) {
            expect(
              buffer.add(<String, dynamic>{...first, 'revision': 2}),
              isTrue,
            );
            expect(buffer.drain((_) => true), 0);
          }
          return true;
        }),
        2,
      );
      expect(revisions, <int>[1, 2]);
      expect(buffer.isEmpty, isTrue);
    });

    test('fallback identity preserves typed ids and has no startup cap', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      for (var requestId = 0; requestId < 160; requestId += 1) {
        expect(buffer.add(pending(requestId: requestId)), isTrue);
      }
      expect(buffer.add(pending(requestId: '0')), isTrue);
      expect(buffer.length, 161);
      expect(buffer.drain((_) => true), 161);
      expect(buffer.isEmpty, isTrue);
    });

    test('dispose clears queued events and rejects future work', () {
      final buffer = CodexServerRequestLifecycleEventBuffer();
      expect(buffer.add(pending(requestId: 1)), isTrue);
      buffer.dispose();

      var routeAttempts = 0;
      expect(buffer.add(pending(requestId: 2)), isFalse);
      expect(
        buffer.drain((_) {
          routeAttempts += 1;
          return true;
        }),
        0,
      );
      expect(routeAttempts, 0);
      expect(buffer.isEmpty, isTrue);
    });
  });

  group(
    'ChatConversationRuntimeCoordinator.replaceConversationSnapshot '
    'preserveLiveStreamingState',
    () {
      final coordinator = ChatConversationRuntimeCoordinator.instance;

      setUp(() {
        coordinator.resetForTest();
      });

      tearDown(() {
        coordinator.resetForTest();
      });

      test(
        'when preserveLiveStreamingState=true the snapshot keeps reducer '
        'push state intact (regression: codex output mid-turn auto-collapse)',
        () {
          const conversationId = 0xC0DE;
          const mode = kChatRuntimeModeCodex;
          coordinator.ensureEphemeralRuntime(
            conversationId: conversationId,
            mode: mode,
          );
          final runtime = coordinator.runtimeFor(
            conversationId: conversationId,
            mode: mode,
          )!;
          // Simulate reducer push-driven streaming state populated by
          // _touchActiveTurn + _appendAssistantText + _appendThinking.
          runtime.isAiResponding = true;
          runtime.currentDispatchTaskId = 'turn-1';
          runtime.lastAgentTaskId = 'turn-1';
          runtime.currentAiMessages['msg-1-codex-agent'] = 'streaming text';
          runtime.currentThinkingMessages['turn-1'] = 'thinking text';
          runtime.currentThinkingStage = ThinkingStage.thinking.value;
          runtime.isDeepThinking = true;

          // Simulate the 2s polling tick deciding the thread looks idle.
          coordinator.replaceConversationSnapshot(
            conversationId: conversationId,
            mode: mode,
            messages: const <ChatMessageModel>[],
            isAiResponding: false,
            currentDispatchTaskId: null,
            currentThinkingStage: ThinkingStage.complete.value,
            preserveLiveStreamingState: true,
          );

          // None of the push-driven fields may have been clobbered: the
          // chat list reads runtime.activeAgentTaskIds and must still see
          // the active turn so the agent run group remains EXPANDED.
          expect(runtime.isAiResponding, isTrue);
          expect(runtime.currentDispatchTaskId, 'turn-1');
          expect(runtime.lastAgentTaskId, 'turn-1');
          expect(runtime.currentAiMessages['msg-1-codex-agent'], 'streaming text');
          expect(runtime.currentThinkingMessages['turn-1'], 'thinking text');
          expect(runtime.currentThinkingStage, ThinkingStage.thinking.value);
          expect(runtime.isDeepThinking, isTrue);
          expect(runtime.activeAgentTaskIds, contains('turn-1'));
        },
      );

      test(
        'when preserveLiveStreamingState=false (default) the snapshot fully '
        'overwrites runtime state (initial session load behaviour)',
        () {
          const conversationId = 0xBEEF;
          const mode = kChatRuntimeModeCodex;
          coordinator.ensureEphemeralRuntime(
            conversationId: conversationId,
            mode: mode,
          );
          final runtime = coordinator.runtimeFor(
            conversationId: conversationId,
            mode: mode,
          )!;
          runtime.isAiResponding = true;
          runtime.currentDispatchTaskId = 'stale-turn';
          runtime.currentAiMessages['old'] = 'old text';

          coordinator.replaceConversationSnapshot(
            conversationId: conversationId,
            mode: mode,
            messages: const <ChatMessageModel>[],
            isAiResponding: false,
            currentDispatchTaskId: null,
          );

          expect(runtime.isAiResponding, isFalse);
          expect(runtime.currentDispatchTaskId, isNull);
          expect(runtime.currentAiMessages, isEmpty);
          expect(runtime.activeAgentTaskIds, isEmpty);
        },
      );
    },
  );

  group('ObservableChatMessageList', () {
    late ObservableChatMessageList list;
    late int notifyCount;

    setUp(() {
      list = ObservableChatMessageList();
      notifyCount = 0;
      list.addListener(() {
        notifyCount += 1;
      });
    });

    tearDown(() {
      list.dispose();
    });

    test('insert triggers list-level notifyListeners', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      expect(notifyCount, 1);
    });

    test('operator []= triggers list-level notifyListeners', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      expect(notifyCount, 1);
      notifyCount = 0;

      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(
        notifyCount,
        1,
        reason:
            'in-place content updates must notify list listeners so that '
            'observers (chat_widgets._handleObservableMessagesChanged) can rebuild',
      );
      expect(list[0].text, 'hi there');
    });

    test('operator []= records content-kind mutation', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(list.lastMutationKind, ChatMessageListMutationKind.content);
    });

    test('per-item notifier still fires on operator []=', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      var perItemNotifyCount = 0;
      ChatMessageModel? lastObserved;
      list.listenableAt(0).addListener(() {
        perItemNotifyCount += 1;
        lastObserved = list[0];
      });

      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(perItemNotifyCount, 1);
      expect(lastObserved?.text, 'hi there');
    });
  });
}
