import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_model_catalog_loader.dart';

void main() {
  test(
    'HTTP 200 data empty stays authoritative and does not use ghost ids',
    () async {
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{
          'model': 'ghost-from-app-server',
        },
        readLocalConfig: () async => _localConfig(),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          return const CodexHttpModelsResult(
            modelIds: <String>[],
            endpoint: 'https://provider.example/v1/models',
            statusCode: 200,
          );
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'ghost-from-app-server'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.providerHttpSucceeded, isTrue);
      expect(result.httpResult?.modelIds, isEmpty);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.source, 'http_v1');
      expect(result.appServerResponse, contains('models'));
    },
  );

  test('provider HTTP failure explicitly enables app-server fallback', () async {
    final failure = StateError('provider unavailable');
    final loader = CodexModelCatalogLoader(
      readRunConfig: () async => const <String, dynamic>{},
      readLocalConfig: () async => _localConfig(),
      readProviderHttpModels: ({
        required String baseUrl,
        required String apiKey,
      }) async {
        throw failure;
      },
      readAppServerModels: () async => const <String, dynamic>{
        'models': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'fallback-model'},
        ],
      },
    );

    final result = await loader.load(remoteRuntime: false);

    expect(result.providerHttpSucceeded, isFalse);
    expect(result.useAppServerModelIds, isTrue);
    expect(result.source, 'app_server_fallback');
    expect(result.httpError, same(failure));
  });

  test(
    'remote runtime never reads phone run config, provider config, or HTTP',
    () async {
      var runConfigReads = 0;
      var localConfigReads = 0;
      var providerHttpReads = 0;
      var appServerReads = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async {
          runConfigReads += 1;
          return const <String, dynamic>{'model': 'phone-local-model'};
        },
        readLocalConfig: () async {
          localConfigReads += 1;
          return _localConfig();
        },
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          providerHttpReads += 1;
          return const CodexHttpModelsResult(
            modelIds: <String>['phone-local-model'],
            endpoint: 'https://phone.example/v1/models',
            statusCode: 200,
          );
        },
        readAppServerModels: () async {
          appServerReads += 1;
          return const <String, dynamic>{
            'models': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'remote-model'},
            ],
          };
        },
      );

      final result = await loader.load(remoteRuntime: true);

      expect(runConfigReads, 0);
      expect(localConfigReads, 0);
      expect(providerHttpReads, 0);
      expect(appServerReads, 1);
      expect(result.source, 'app_server_remote');
      expect(result.useAppServerModelIds, isTrue);
      expect(result.runConfigResponse, isEmpty);
    },
  );

  test('CodexStatus parses native session generation', () {
    final status = CodexStatus.fromMap(const <String, dynamic>{
      'connected': true,
      'ready': true,
      'codexHome': '/data/codex',
      'sessionGeneration': '41',
    });

    expect(status.sessionGeneration, 41);
  });

  test('runtime identity changes when the same endpoint reconnects', () {
    const firstLocal = CodexStatus(
      connected: true,
      ready: true,
      codexHome: '/data/codex',
      sessionGeneration: 41,
    );
    const nextLocal = CodexStatus(
      connected: true,
      ready: true,
      codexHome: '/data/codex',
      sessionGeneration: 42,
    );
    const firstRemote = CodexStatus(
      connected: true,
      ready: true,
      runtime: 'remote',
      remoteEnabled: true,
      remoteBridgeUrl: 'wss://pc.example/bridge',
      sessionGeneration: 7,
    );
    const nextRemote = CodexStatus(
      connected: true,
      ready: true,
      runtime: 'remote',
      remoteEnabled: true,
      remoteBridgeUrl: 'wss://pc.example/bridge',
      sessionGeneration: 8,
    );

    expect(
      codexModelRuntimeIdentity(firstLocal),
      isNot(codexModelRuntimeIdentity(nextLocal)),
    );
    expect(
      codexModelRuntimeIdentity(firstRemote),
      isNot(codexModelRuntimeIdentity(nextRemote)),
    );
  });

  test('same endpoint reconnect rejects the prior session request', () {
    const firstSession = CodexStatus(
      connected: true,
      ready: true,
      runtime: 'remote',
      remoteEnabled: true,
      remoteBridgeUrl: 'wss://pc.example/bridge',
      sessionGeneration: 7,
    );
    const nextSession = CodexStatus(
      connected: true,
      ready: true,
      runtime: 'remote',
      remoteEnabled: true,
      remoteBridgeUrl: 'wss://pc.example/bridge',
      sessionGeneration: 8,
    );
    final gate = CodexModelCatalogRequestGate();
    final priorRequest = gate.begin(
      runtimeIdentity: codexModelRuntimeIdentity(firstSession),
    );

    expect(
      gate.isCurrent(
        priorRequest,
        runtimeIdentity: codexModelRuntimeIdentity(nextSession),
      ),
      isFalse,
    );
  });

  test('request generations are latest-wins across provider refreshes', () {
    final gate = CodexModelCatalogRequestGate();
    final oldProviderRequest = gate.begin(runtimeIdentity: 'local:/codex');
    final newProviderRequest = gate.begin(runtimeIdentity: 'local:/codex');

    expect(
      gate.isCurrent(
        oldProviderRequest,
        runtimeIdentity: 'local:/codex',
      ),
      isFalse,
    );
    expect(
      gate.isCurrent(
        newProviderRequest,
        runtimeIdentity: 'local:/codex',
      ),
      isTrue,
    );
    expect(
      gate.isCurrent(
        newProviderRequest,
        runtimeIdentity: 'remote:wss://pc',
      ),
      isFalse,
    );

    gate.invalidate();
    expect(
      gate.isCurrent(
        newProviderRequest,
        runtimeIdentity: 'local:/codex',
      ),
      isFalse,
    );
  });
}

CodexLocalConfig _localConfig() {
  return const CodexLocalConfig(
    baseUrl: 'https://provider.example/v1',
    model: 'provider-model',
    apiKey: 'test-key',
  );
}
