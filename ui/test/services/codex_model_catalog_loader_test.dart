import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_model_catalog_loader.dart';
import 'package:ui/services/model_provider_config_service.dart';

void main() {
  test(
    'HTTP 200 data empty stays authoritative and does not use ghost ids',
    () async {
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{
          'model': 'ghost-from-app-server',
        },
        readActiveProviderId: () async => 'provider-a',
        readProviderProfile: ({
          required String providerId,
        }) async => _providerProfile(id: providerId),
        readManualProviderModels: ({
          required String providerId,
        }) async => const <String>[],
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
        writeCachedProviderModels: ({
          required String providerId,
          required String apiBase,
          required List<ProviderModelOption> models,
        }) async {},
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.providerHttpSucceeded, isTrue);
      expect(result.httpResult?.modelIds, isEmpty);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.source, 'http_v1');
      expect(result.providerIdentity, 'local:provider=provider-a');
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
    'local supplier catalog merges manual ids and caches fresh HTTP ids',
    () async {
      String? cachedProviderId;
      String? cachedApiBase;
      List<String>? cachedModelIds;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveProviderId: () async => 'provider-a',
        readProviderProfile: ({
          required String providerId,
        }) async => _providerProfile(id: providerId),
        readManualProviderModels: ({
          required String providerId,
        }) async {
          expect(providerId, 'provider-a');
          return const <String>['manual-model'];
        },
        readLocalConfig: () async => _localConfig(),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          return const CodexHttpModelsResult(
            modelIds: <String>['remote-model'],
            endpoint: 'https://provider.example/v1/models',
            statusCode: 200,
          );
        },
        writeCachedProviderModels: ({
          required String providerId,
          required String apiBase,
          required List<ProviderModelOption> models,
        }) async {
          cachedProviderId = providerId;
          cachedApiBase = apiBase;
          cachedModelIds = models.map((item) => item.id).toList();
        },
        readAppServerModels: () async => const <String, dynamic>{},
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.providerModelIds, ['manual-model', 'remote-model']);
      expect(cachedProviderId, 'provider-a');
      expect(cachedApiBase, 'https://provider.example/v1');
      expect(cachedModelIds, ['remote-model']);
    },
  );

  test(
    'HTTP failure uses only the active supplier manual and base-scoped cache',
    () async {
      final failure = StateError('provider unavailable');
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveProviderId: () async => 'provider-a',
        readProviderProfile: ({
          required String providerId,
        }) async => _providerProfile(id: providerId),
        readManualProviderModels: ({
          required String providerId,
        }) async => const <String>['manual-model'],
        readCachedProviderModels: ({
          required String providerId,
          required String apiBase,
        }) async {
          expect(providerId, 'provider-a');
          expect(apiBase, 'https://provider.example/v1');
          return const <ProviderModelOption>[
            ProviderModelOption(
              id: 'cached-model',
              displayName: 'cached-model',
            ),
          ];
        },
        readLocalConfig: () async => _localConfig(),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          throw failure;
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'unscoped-app-server-model'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.source, 'provider_library_cache');
      expect(result.providerHttpSucceeded, isFalse);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.providerModelIds, ['manual-model', 'cached-model']);
      expect(result.httpError, same(failure));
    },
  );

  test(
    'mismatched active supplier and native config never touch its model library',
    () async {
      var manualReads = 0;
      var cacheWrites = 0;
      var providerHttpReads = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveProviderId: () async => 'provider-a',
        readProviderProfile: ({
          required String providerId,
        }) async => _providerProfile(id: providerId),
        readManualProviderModels: ({
          required String providerId,
        }) async {
          manualReads += 1;
          return const <String>['wrong-manual-model'];
        },
        readLocalConfig: () async => _localConfig(
          baseUrl: 'https://provider-b.example/v1',
          apiKey: 'provider-b-key',
        ),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          providerHttpReads += 1;
          return const CodexHttpModelsResult(
            modelIds: <String>['wrong-remote-model'],
            endpoint: 'https://provider-b.example/v1/models',
            statusCode: 200,
          );
        },
        writeCachedProviderModels: ({
          required String providerId,
          required String apiBase,
          required List<ProviderModelOption> models,
        }) async {
          cacheWrites += 1;
        },
        readAppServerModels: () async => const <String, dynamic>{},
      );

      await expectLater(
        loader.load(remoteRuntime: false),
        throwsA(isA<StateError>()),
      );

      expect(manualReads, 0);
      expect(providerHttpReads, 0);
      expect(cacheWrites, 0);
    },
  );

  test(
    'same supplier id changing endpoint during HTTP cannot write stale cache',
    () async {
      var httpCompleted = false;
      var cacheWrites = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveProviderId: () async => 'provider-a',
        readProviderProfile: ({required String providerId}) async {
          return _providerProfile(
            id: providerId,
            baseUrl: httpCompleted
                ? 'https://changed.example/v1'
                : 'https://provider.example/v1',
          );
        },
        readManualProviderModels: ({
          required String providerId,
        }) async => const <String>['manual-model'],
        readLocalConfig: () async => _localConfig(),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          httpCompleted = true;
          return const CodexHttpModelsResult(
            modelIds: <String>['late-model'],
            endpoint: 'https://provider.example/v1/models',
            statusCode: 200,
          );
        },
        writeCachedProviderModels: ({
          required String providerId,
          required String apiBase,
          required List<ProviderModelOption> models,
        }) async {
          cacheWrites += 1;
        },
        readAppServerModels: () async => const <String, dynamic>{},
      );

      await expectLater(
        loader.load(remoteRuntime: false),
        throwsA(isA<StateError>()),
      );

      expect(cacheWrites, 0);
    },
  );

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

  test('provider revision makes a late catalog request non-current', () {
    final gate = CodexModelCatalogRequestGate();
    const oldIdentity =
        'local:/codex|provider=provider-a|providerRevision=7';
    const newIdentity =
        'local:/codex|provider=provider-b|providerRevision=8';
    final oldProviderRequest = gate.begin(runtimeIdentity: oldIdentity);
    final newProviderRequest = gate.begin(runtimeIdentity: newIdentity);

    expect(
      gate.isCurrent(
        oldProviderRequest,
        runtimeIdentity: newIdentity,
      ),
      isFalse,
    );
    expect(
      gate.isCurrent(
        newProviderRequest,
        runtimeIdentity: newIdentity,
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
        runtimeIdentity: newIdentity,
      ),
      isFalse,
    );
  });
}

CodexLocalConfig _localConfig({
  String baseUrl = 'https://provider.example/v1',
  String apiKey = 'test-key',
}) {
  return CodexLocalConfig(
    baseUrl: baseUrl,
    model: 'provider-model',
    apiKey: apiKey,
  );
}

ModelProviderProfileSummary _providerProfile({
  String id = 'provider-a',
  String baseUrl = 'https://provider.example/v1',
  String apiKey = 'test-key',
}) {
  return ModelProviderProfileSummary(
    id: id,
    name: 'Provider $id',
    baseUrl: baseUrl,
    apiKey: apiKey,
    customHeaders: const <String, String>{},
    sourceType: 'custom',
    readOnly: false,
    ready: true,
    statusText: '',
    configured: true,
    wireApi: 'responses',
  );
}
