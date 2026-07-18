import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/voice_playback_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assistCoreChannel = MethodChannel('cn.com.omnimind.bot/AssistCoreEvent');
  const voiceChannel = MethodChannel('cn.com.omnimind.bot/VoicePlayback');

  late List<Map<String, dynamic>> sceneBindings;
  late Map<String, dynamic> sceneVoiceConfig;
  late List<MethodCall> voiceCalls;
  Completer<void>? sceneConfigGate;
  Completer<void>? firstSpeakGate;
  Completer<void>? firstSpeakStarted;

  setUp(() async {
    sceneBindings = <Map<String, dynamic>>[];
    sceneVoiceConfig = <String, dynamic>{
      'autoPlay': false,
      'voiceId': 'default_zh',
      'stylePreset': '默认',
      'customStyle': '',
    };
    voiceCalls = <MethodCall>[];
    sceneConfigGate = null;
    firstSpeakGate = null;
    firstSpeakStarted = null;
    await VoicePlaybackCoordinator.instance.debugResetForTest();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(assistCoreChannel, (call) async {
          final gate = sceneConfigGate;
          if (gate != null) {
            await gate.future;
          }
          switch (call.method) {
            case 'getSceneModelBindings':
              return sceneBindings;
            case 'getSceneVoiceConfig':
              return sceneVoiceConfig;
            default:
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(voiceChannel, (call) async {
          voiceCalls.add(call);
          if (call.method == 'speakText') {
            final started = firstSpeakStarted;
            if (started != null && !started.isCompleted) {
              started.complete();
            }
            final gate = firstSpeakGate;
            if (gate != null) {
              await gate.future;
            }
          }
          return true;
        });
  });

  tearDown(() async {
    await VoicePlaybackCoordinator.instance.debugResetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(assistCoreChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(voiceChannel, null);
  });

  test('auto play queues sealed segments incrementally', () async {
    sceneBindings = <Map<String, dynamic>>[
      <String, dynamic>{
        'sceneId': 'scene.voice',
        'providerProfileId': 'provider-1',
        'modelId': 'mimo-v2-tts',
      },
    ];
    sceneVoiceConfig = <String, dynamic>{
      'autoPlay': true,
      'voiceId': 'default_zh',
      'stylePreset': '默认',
      'customStyle': '',
    };

    await VoicePlaybackCoordinator.instance.ensureInitialized();
    await VoicePlaybackCoordinator.instance.onAssistantMessageUpdated(
      messageId: 'message-1',
      text: '第一句。第二句',
      isFinal: false,
    );
    await Future<void>.delayed(Duration.zero);

    expect(voiceCalls, hasLength(1));
    expect(voiceCalls.first.method, 'speakText');
    expect(voiceCalls.first.arguments['text'], '第一句。');
    expect(voiceCalls.first.arguments['enqueue'], false);

    await VoicePlaybackCoordinator.instance.onAssistantMessageCompleted(
      messageId: 'message-1',
      text: '第一句。第二句',
    );
    await Future<void>.delayed(Duration.zero);

    expect(voiceCalls, hasLength(2));
    expect(voiceCalls.last.arguments['text'], '第二句');
    expect(voiceCalls.last.arguments['enqueue'], true);
  });

  test('serializes rapid cumulative updates for the same message', () async {
    sceneBindings = <Map<String, dynamic>>[
      <String, dynamic>{
        'sceneId': 'scene.voice',
        'providerProfileId': 'provider-1',
        'modelId': 'mimo-v2-tts',
      },
    ];
    sceneVoiceConfig = <String, dynamic>{
      'autoPlay': true,
      'voiceId': 'default_zh',
      'stylePreset': '默认',
      'customStyle': '',
    };
    await VoicePlaybackCoordinator.instance.ensureInitialized();

    final gate = Completer<void>();
    final started = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete();
      }
    });
    firstSpeakGate = gate;
    firstSpeakStarted = started;

    final firstUpdate =
        VoicePlaybackCoordinator.instance.onAssistantMessageUpdated(
      messageId: 'message-rapid-updates',
      text: '第一句。',
      isFinal: false,
    );
    await started.future;

    final secondUpdate =
        VoicePlaybackCoordinator.instance.onAssistantMessageUpdated(
      messageId: 'message-rapid-updates',
      text: '第一句。第二句。',
      isFinal: true,
    );
    await Future<void>.delayed(Duration.zero);

    final callsBeforeRelease = List<MethodCall>.from(voiceCalls);
    gate.complete();
    await Future.wait<void>(<Future<void>>[firstUpdate, secondUpdate]);

    expect(callsBeforeRelease, hasLength(1));
    expect(
      voiceCalls.map((call) => call.arguments['text']),
      <String>['第一句。', '第二句。'],
    );
    expect(
      voiceCalls.map((call) => call.arguments['enqueue']),
      <bool>[false, true],
    );
  });

  test('concurrent update awaits the in-flight configuration load', () async {
    sceneBindings = <Map<String, dynamic>>[
      <String, dynamic>{
        'sceneId': 'scene.voice',
        'providerProfileId': 'provider-1',
        'modelId': 'mimo-v2-tts',
      },
    ];
    sceneVoiceConfig = <String, dynamic>{
      'autoPlay': true,
      'voiceId': 'default_zh',
      'stylePreset': '默认',
      'customStyle': '',
    };
    final gate = Completer<void>();
    sceneConfigGate = gate;

    final initialization =
        VoicePlaybackCoordinator.instance.ensureInitialized();
    final update = VoicePlaybackCoordinator.instance.onAssistantMessageUpdated(
      messageId: 'message-concurrent-init',
      text: '首段不能丢。',
      isFinal: true,
    );

    gate.complete();
    await Future.wait<void>(<Future<void>>[initialization, update]);

    expect(voiceCalls, hasLength(1));
    expect(voiceCalls.single.method, 'speakText');
    expect(voiceCalls.single.arguments['text'], '首段不能丢。');
  });
}
