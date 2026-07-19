import 'package:flutter_test/flutter_test.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_model_catalog_loader.dart';
import 'package:ui/services/codex_supplier_store.dart';

void main() {
  test(
    'HTTP 200 data empty stays authoritative and does not use ghost ids',
    () async {
      final library = _libraryWith(
        models: const <CodexSupplierModelEntry>[],
      );
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{
          'model': 'ghost-from-app-server',
        },
        readActiveSupplier: () async => library.activeSupplier,
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
        mergeFetchedModels: ({
          required String supplierId,
          required List<String> remoteModelIds,
          bool defaultEnableNew = true,
        }) async {
          expect(supplierId, 'supplier-a');
          expect(remoteModelIds, isEmpty);
          return library.activeSupplier!;
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
      expect(result.providerModelIds, isEmpty);
      expect(result.providerIdentity, 'local:provider=supplier-a');
      expect(result.appServerResponse, contains('models'));
    },
  );

  test(
    'HTTP failure keeps Codex supplier enabled ids and never falls back to Agent',
    () async {
      final failure = StateError('provider unavailable');
      var mergeCalls = 0;
      final library = _libraryWith(
        models: const <CodexSupplierModelEntry>[
          CodexSupplierModelEntry(id: 'enabled-a', enabled: true),
          CodexSupplierModelEntry(id: 'disabled-b', enabled: false),
        ],
      );
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async => library.activeSupplier,
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          throw failure;
        },
        mergeFetchedModels: ({
          required String supplierId,
          required List<String> remoteModelIds,
          bool defaultEnableNew = true,
        }) async {
          mergeCalls += 1;
          return library.activeSupplier!;
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'agent-ghost-model'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.providerHttpSucceeded, isFalse);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.source, 'codex_supplier_library');
      expect(result.source, isNot('provider_library_cache'));
      expect(result.providerModelIds, ['enabled-a']);
      expect(result.httpError, same(failure));
      expect(mergeCalls, 0);
    },
  );

  test(
    'successful HTTP merges remote ids into supplier library and returns only enabled',
    () async {
      final models = <CodexSupplierModelEntry>[
        const CodexSupplierModelEntry(id: 'kept-enabled', enabled: true),
        const CodexSupplierModelEntry(id: 'user-disabled', enabled: false),
      ];
      var mergeCalls = 0;
      List<String>? mergedRemoteIds;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async => CodexSupplierRecord(
          id: 'supplier-a',
          baseUrl: 'https://provider.example/v1',
          apiKey: 'test-key',
          models: List<CodexSupplierModelEntry>.unmodifiable(models),
          activeModelId: 'kept-enabled',
        ).normalized(),
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          expect(baseUrl, 'https://provider.example/v1');
          expect(apiKey, 'test-key');
          return const CodexHttpModelsResult(
            modelIds: <String>['kept-enabled', 'user-disabled', 'new-remote'],
            endpoint: 'https://provider.example/v1/models',
            statusCode: 200,
          );
        },
        mergeFetchedModels: ({
          required String supplierId,
          required List<String> remoteModelIds,
          bool defaultEnableNew = true,
        }) async {
          mergeCalls += 1;
          expect(supplierId, 'supplier-a');
          expect(defaultEnableNew, isTrue);
          mergedRemoteIds = List<String>.from(remoteModelIds);
          // Simulate store merge: new id enabled by default; keep prior flags.
          final byId = <String, CodexSupplierModelEntry>{
            for (final model in models) model.id: model,
          };
          for (final id in remoteModelIds) {
            byId.putIfAbsent(
              id,
              () => CodexSupplierModelEntry(
                id: id,
                enabled: defaultEnableNew,
              ),
            );
          }
          models
            ..clear()
            ..addAll(byId.values);
          return CodexSupplierRecord(
            id: 'supplier-a',
            baseUrl: 'https://provider.example/v1',
            apiKey: 'test-key',
            models: List<CodexSupplierModelEntry>.unmodifiable(models),
            activeModelId: 'kept-enabled',
          ).normalized();
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'app-server-only'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(mergeCalls, 1);
      expect(mergedRemoteIds, ['kept-enabled', 'user-disabled', 'new-remote']);
      expect(result.providerHttpSucceeded, isTrue);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.source, 'http_v1');
      // enabled only: kept-enabled + new-remote; user-disabled stays off.
      expect(result.providerModelIds, ['kept-enabled', 'new-remote']);
      expect(result.providerModelIds, isNot(contains('app-server-only')));
      expect(result.providerModelIds, isNot(contains('user-disabled')));
    },
  );

  test(
    'returns only enabled models from Codex supplier library',
    () async {
      final library = _libraryWith(
        models: const <CodexSupplierModelEntry>[
          CodexSupplierModelEntry(id: 'on-1', enabled: true),
          CodexSupplierModelEntry(id: 'off-1', enabled: false),
          CodexSupplierModelEntry(id: 'on-2', enabled: true),
        ],
      );
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async => library.activeSupplier,
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          throw StateError('skip http');
        },
        readAppServerModels: () async => const <String, dynamic>{},
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.providerModelIds, ['on-1', 'on-2']);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.source, 'codex_supplier_library');
    },
  );

  test(
    'HTTP failure never emits provider_library_cache or Agent ghost ids',
    () async {
      final failure = FormatException('unexpected body');
      final library = _libraryWith(
        models: const <CodexSupplierModelEntry>[
          CodexSupplierModelEntry(id: 'lib-model', enabled: true),
        ],
      );
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async => library.activeSupplier,
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          throw failure;
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'from-app-server'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(result.source, 'codex_supplier_library');
      expect(result.source, isNot('provider_library_cache'));
      expect(result.providerModelIds, ['lib-model']);
      expect(result.useAppServerModelIds, isFalse);
      expect(result.httpError, same(failure));
    },
  );

  test(
    'supplier identity changing during HTTP cannot merge stale catalog',
    () async {
      var httpCompleted = false;
      var mergeCalls = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async {
          if (!httpCompleted) {
            return CodexSupplierRecord(
              id: 'supplier-a',
              baseUrl: 'https://provider.example/v1',
              apiKey: 'test-key',
              models: const <CodexSupplierModelEntry>[
                CodexSupplierModelEntry(id: 'before', enabled: true),
              ],
              activeModelId: 'before',
            ).normalized();
          }
          // Mid-flight switch to another supplier endpoint.
          return CodexSupplierRecord(
            id: 'supplier-a',
            baseUrl: 'https://changed.example/v1',
            apiKey: 'test-key',
            models: const <CodexSupplierModelEntry>[
              CodexSupplierModelEntry(id: 'after', enabled: true),
            ],
            activeModelId: 'after',
          ).normalized();
        },
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
        mergeFetchedModels: ({
          required String supplierId,
          required List<String> remoteModelIds,
          bool defaultEnableNew = true,
        }) async {
          mergeCalls += 1;
          return CodexSupplierRecord(
            id: supplierId,
            baseUrl: 'https://provider.example/v1',
            apiKey: 'test-key',
            models: remoteModelIds
                .map((id) => CodexSupplierModelEntry(id: id))
                .toList(growable: false),
          ).normalized();
        },
        readAppServerModels: () async => const <String, dynamic>{},
      );

      await expectLater(
        loader.load(remoteRuntime: false),
        throwsA(isA<StateError>()),
      );
      expect(mergeCalls, 0);
    },
  );

  test(
    'missing active supplier falls back to app-server without Agent cache',
    () async {
      var httpReads = 0;
      var mergeCalls = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async => const <String, dynamic>{},
        readActiveSupplier: () async => null,
        readProviderHttpModels: ({
          required String baseUrl,
          required String apiKey,
        }) async {
          httpReads += 1;
          return const CodexHttpModelsResult(
            modelIds: <String>['should-not-run'],
            endpoint: 'https://provider.example/v1/models',
            statusCode: 200,
          );
        },
        mergeFetchedModels: ({
          required String supplierId,
          required List<String> remoteModelIds,
          bool defaultEnableNew = true,
        }) async {
          mergeCalls += 1;
          throw StateError('merge must not run without supplier');
        },
        readAppServerModels: () async => const <String, dynamic>{
          'models': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'bootstrap-model'},
          ],
        },
      );

      final result = await loader.load(remoteRuntime: false);

      expect(httpReads, 0);
      expect(mergeCalls, 0);
      expect(result.source, 'app_server_fallback');
      expect(result.useAppServerModelIds, isTrue);
      expect(result.providerIdentity, 'local:unavailable');
    },
  );

  test(
    'remote runtime never reads supplier library or provider HTTP',
    () async {
      var runConfigReads = 0;
      var supplierReads = 0;
      var providerHttpReads = 0;
      var appServerReads = 0;
      final loader = CodexModelCatalogLoader(
        readRunConfig: () async {
          runConfigReads += 1;
          return const <String, dynamic>{'model': 'phone-local-model'};
        },
        readActiveSupplier: () async {
          supplierReads += 1;
          return _libraryWith().activeSupplier;
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
      expect(supplierReads, 0);
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

CodexSupplierLibrary _libraryWith({
  String supplierId = 'supplier-a',
  String baseUrl = 'https://provider.example/v1',
  String apiKey = 'test-key',
  List<CodexSupplierModelEntry> models = const <CodexSupplierModelEntry>[
    CodexSupplierModelEntry(id: 'default-model', enabled: true),
  ],
}) {
  final record = CodexSupplierRecord(
    id: supplierId,
    baseUrl: baseUrl,
    apiKey: apiKey,
    models: models,
    activeModelId: models
        .where((item) => item.enabled)
        .map((item) => item.id)
        .firstWhere((id) => id.isNotEmpty, orElse: () => ''),
  ).normalized();
  return CodexSupplierLibrary(
    activeSupplierId: record.id,
    suppliers: <CodexSupplierRecord>[record],
  );
}
