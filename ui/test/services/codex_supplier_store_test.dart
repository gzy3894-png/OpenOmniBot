import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_supplier_store.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/storage_service.dart';

ModelProviderProfileSummary _profile({
  required String id,
  String name = 'Memo',
  String baseUrl = 'https://api.example.com/v1',
  String apiKey = 'sk-test',
}) {
  return ModelProviderProfileSummary(
    id: id,
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    customHeaders: const <String, String>{},
    sourceType: 'custom',
    readOnly: false,
    ready: true,
    statusText: '',
    configured: true,
    protocolType: 'openai_compatible',
    wireApi: 'responses',
  );
}

CodexSupplierRecord _supplier({
  String id = 'sup-a',
  String baseUrl = 'https://api.example.com/v1',
  String apiKey = 'sk-test',
  List<CodexSupplierModelEntry>? models,
  String activeModelId = 'gpt-4o',
  String activeEffort = 'medium',
}) {
  return CodexSupplierRecord(
    id: id,
    memoName: 'A',
    baseUrl: baseUrl,
    apiKey: apiKey,
    models: models ??
        const <CodexSupplierModelEntry>[
          CodexSupplierModelEntry(id: 'gpt-4o', enabled: true),
          CodexSupplierModelEntry(id: 'o3', enabled: false),
        ],
    activeModelId: activeModelId,
    activeEffort: activeEffort,
  ).normalized();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.init();
    CodexSupplierStore.debugResetMemory();
    CodexSupplierStore.revision.value = 0;
    // Default: skip Agent runtime migration path for CRUD/merge/validate tests.
    // Migration groups clear this flag and exercise ensureMigrated injects.
    await StorageService.setBool(CodexSupplierStore.migrationFlagKey, true);
  });

  tearDown(() {
    CodexSupplierStore.debugResetMemory();
    CodexSupplierStore.revision.value = 0;
  });

  Future<void> clearMigrationFlag() async {
    await StorageService.setBool(CodexSupplierStore.migrationFlagKey, false);
    CodexSupplierStore.debugResetMemory();
  }

  group('isolation', () {
    test(
      'writes only codex_suppliers_v1 and never touches Agent codex_provider_state_v1',
      () async {
        await CodexSupplierStore.upsert(_supplier());
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(CodexSupplierStore.storageKey), isNotNull);
        expect(prefs.getString(CodexSupplierStore.storageKey), isNotEmpty);
        expect(prefs.getString('codex_provider_state_v1'), isNull);
        expect(prefs.getString('model_provider_profiles_v1'), isNull);
      },
    );

    test(
      'ensureMigrated with injects does not call Agent listProfiles runtime path',
      () async {
        await clearMigrationFlag();
        var listProfilesCalls = 0;
        await CodexSupplierStore.ensureMigrated(
          listProfiles: () async {
            listProfilesCalls += 1;
            return ModelProviderProfilesPayload(
              profiles: <ModelProviderProfileSummary>[
                _profile(id: 'agent-1', name: 'Agent One'),
              ],
              editingProfileId: 'agent-1',
            );
          },
          getStoredModelsForProfile: (profile) async {
            return const <ProviderModelOption>[
              ProviderModelOption(id: 'm1', displayName: 'M1'),
              ProviderModelOption(id: 'm2', displayName: 'M2'),
            ];
          },
          readLegacyProviderState: () => const CodexProviderState(
            activeProviderId: 'agent-1',
            currentModels: <String, String>{'agent-1': 'm2'},
          ),
          readLocalConfig: () async => const CodexLocalConfig(
            baseUrl: '',
            model: '',
            apiKey: '',
          ),
        );

        expect(listProfilesCalls, 1);
        final library = CodexSupplierStore.read();
        expect(library.suppliers, hasLength(1));
        expect(library.activeSupplierId, 'agent-1');
        expect(library.activeSupplier?.activeModelId, 'm2');
        expect(library.activeSupplier?.enabledModelIds, <String>['m1', 'm2']);

        listProfilesCalls = 0;
        await CodexSupplierStore.ensureMigrated(
          listProfiles: () async {
            listProfilesCalls += 1;
            fail('listProfiles must not be called after migration flag');
          },
        );
        expect(listProfilesCalls, 0);
      },
    );
  });

  group('migration once', () {
    test('migration flag is persisted and blocks second copy', () async {
      await clearMigrationFlag();
      var copies = 0;
      await CodexSupplierStore.ensureMigrated(
        listProfiles: () async {
          copies += 1;
          return ModelProviderProfilesPayload(
            profiles: <ModelProviderProfileSummary>[
              _profile(id: 'p1'),
            ],
            editingProfileId: 'p1',
          );
        },
        getStoredModelsForProfile: (_) async => const <ProviderModelOption>[
          ProviderModelOption(id: 'alpha', displayName: 'alpha'),
        ],
        readLegacyProviderState: () => const CodexProviderState(
          activeProviderId: 'p1',
          currentModels: <String, String>{'p1': 'alpha'},
        ),
        readLocalConfig: () async =>
            const CodexLocalConfig(baseUrl: '', model: '', apiKey: ''),
      );
      expect(copies, 1);
      expect(
        StorageService.getBool(
          CodexSupplierStore.migrationFlagKey,
          defaultValue: false,
        ),
        isTrue,
      );

      final first = CodexSupplierStore.read();
      expect(first.suppliers.single.id, 'p1');

      // Wipe Codex library only — migration flag remains, so no re-copy.
      await StorageService.setString(CodexSupplierStore.storageKey, '');
      CodexSupplierStore.debugResetMemory();
      expect(
        StorageService.getBool(
          CodexSupplierStore.migrationFlagKey,
          defaultValue: false,
        ),
        isTrue,
      );

      copies = 0;
      await CodexSupplierStore.ensureMigrated(
        listProfiles: () async {
          copies += 1;
          return const ModelProviderProfilesPayload(
            profiles: <ModelProviderProfileSummary>[],
            editingProfileId: '',
          );
        },
      );
      expect(copies, 0);
      expect(CodexSupplierStore.read().suppliers, isEmpty);
    });

    test(
      'memory-only path marks migrated so second call skips injects',
      () async {
        await clearMigrationFlag();
        var calls = 0;
        await CodexSupplierStore.ensureMigrated(
          listProfiles: () async {
            calls += 1;
            return ModelProviderProfilesPayload(
              profiles: <ModelProviderProfileSummary>[_profile(id: 'mem-1')],
              editingProfileId: 'mem-1',
            );
          },
          getStoredModelsForProfile: (_) async => const <ProviderModelOption>[
            ProviderModelOption(id: 'x', displayName: 'x'),
          ],
          readLegacyProviderState: () => const CodexProviderState(
            activeProviderId: 'mem-1',
            currentModels: <String, String>{'mem-1': 'x'},
          ),
          readLocalConfig: () async =>
              const CodexLocalConfig(baseUrl: '', model: '', apiKey: ''),
        );
        expect(calls, 1);

        calls = 0;
        await CodexSupplierStore.ensureMigrated(
          listProfiles: () async {
            calls += 1;
            fail('must not re-run migration');
          },
        );
        expect(calls, 0);
      },
    );
  });

  group('mergeFetchedModels default enable new', () {
    test('new remote ids default enabled; existing keep user flag', () async {
      await CodexSupplierStore.upsert(
        _supplier(
          models: const <CodexSupplierModelEntry>[
            CodexSupplierModelEntry(id: 'old-on', enabled: true),
            CodexSupplierModelEntry(id: 'old-off', enabled: false),
          ],
          activeModelId: 'old-on',
        ),
      );

      final merged = await CodexSupplierStore.mergeFetchedModels(
        supplierId: 'sup-a',
        remoteModelIds: const <String>['old-on', 'old-off', 'brand-new'],
      );

      final byId = <String, CodexSupplierModelEntry>{
        for (final m in merged.models) m.id: m,
      };
      expect(byId['old-on']!.enabled, isTrue);
      expect(byId['old-off']!.enabled, isFalse);
      expect(byId['brand-new']!.enabled, isTrue);
      expect(merged.activeModelId, 'old-on');
    });
  });

  group('validateForSwitch', () {
    test('fails without base url', () {
      final result = CodexSupplierStore.validateForSwitch(
        _supplier(baseUrl: ''),
      );
      expect(result.isOk, isFalse);
      expect(result.reason, contains('API Base'));
    });

    test('fails without api key', () {
      final result = CodexSupplierStore.validateForSwitch(
        _supplier(apiKey: '  '),
      );
      expect(result.isOk, isFalse);
      expect(result.reason, contains('API Key'));
    });

    test('fails when no enabled model', () {
      final result = CodexSupplierStore.validateForSwitch(
        _supplier(
          models: const <CodexSupplierModelEntry>[
            CodexSupplierModelEntry(id: 'a', enabled: false),
          ],
          activeModelId: '',
        ),
      );
      expect(result.isOk, isFalse);
      expect(result.reason, contains('at least one model'));
    });

    test('fails when active model not in enabled set', () {
      final raw = CodexSupplierRecord(
        id: 'sup-a',
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        models: const <CodexSupplierModelEntry>[
          CodexSupplierModelEntry(id: 'a', enabled: true),
          CodexSupplierModelEntry(id: 'b', enabled: false),
        ],
        activeModelId: 'b',
      );
      final result = CodexSupplierStore.validateForSwitch(raw);
      expect(result.isOk, isFalse);
      expect(result.reason, contains('Active model'));
    });

    test('ok for valid supplier', () {
      final result = CodexSupplierStore.validateForSwitch(_supplier());
      expect(result.isOk, isTrue);
      expect(result.reason, isEmpty);
    });
  });

  group('memory fallback', () {
    test('write bumps revision and round-trips through Storage', () async {
      final before = CodexSupplierStore.revision.value;
      await CodexSupplierStore.write(
        CodexSupplierLibrary(
          activeSupplierId: 'm1',
          suppliers: <CodexSupplierRecord>[_supplier(id: 'm1')],
        ),
      );
      expect(CodexSupplierStore.revision.value, before + 1);
      expect(CodexSupplierStore.read().activeSupplierId, 'm1');
      expect(CodexSupplierStore.read().find('m1')?.apiKey, 'sk-test');
    });

    test(
      'write/read use memory when StorageService is unavailable',
      () async {
        CodexSupplierStore.debugForceMemoryOnly(true);
        final before = CodexSupplierStore.revision.value;
        await CodexSupplierStore.write(
          CodexSupplierLibrary(
            activeSupplierId: 'mem',
            suppliers: <CodexSupplierRecord>[_supplier(id: 'mem')],
          ),
        );
        expect(CodexSupplierStore.revision.value, before + 1);
        expect(CodexSupplierStore.read().find('mem')?.id, 'mem');
        // Storage key must stay empty — memory-only path never wrote prefs.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(CodexSupplierStore.storageKey), isNull);
      },
    );
  });

  group('search filter', () {
    test('filterCodexSupplierModels is case-insensitive on id and name', () {
      const models = <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'GPT-4o', displayName: 'Flagship'),
        CodexSupplierModelEntry(id: 'o3-mini', displayName: 'Small'),
        CodexSupplierModelEntry(id: 'claude-3', displayName: 'Anthropic'),
      ];
      final byId = filterCodexSupplierModels(models, 'gpt');
      expect(byId.map((e) => e.id).toList(), <String>['GPT-4o']);

      final byName = filterCodexSupplierModels(models, 'ANTHRO');
      expect(byName.map((e) => e.id).toList(), <String>['claude-3']);

      final empty = filterCodexSupplierModels(models, '   ');
      expect(empty, hasLength(3));
    });
  });

  group('crud + revision', () {
    test('upsert delete setActive and revision notifications', () async {
      final revs = <int>[];
      void listener() => revs.add(CodexSupplierStore.revision.value);
      CodexSupplierStore.revision.addListener(listener);
      addTearDown(() => CodexSupplierStore.revision.removeListener(listener));

      await CodexSupplierStore.upsert(_supplier(id: 'a'));
      await CodexSupplierStore.upsert(
        _supplier(id: 'b', activeModelId: 'gpt-4o'),
      );
      expect(CodexSupplierStore.read().suppliers, hasLength(2));

      await CodexSupplierStore.setActiveSupplierId('b');
      expect(CodexSupplierStore.read().activeSupplierId, 'b');

      await CodexSupplierStore.delete('b');
      expect(CodexSupplierStore.read().find('b'), isNull);
      expect(CodexSupplierStore.read().activeSupplierId, 'a');
      expect(revs, isNotEmpty);
    });

    test('setVisibleModelsEnabled and invertVisibleModels', () async {
      await CodexSupplierStore.upsert(
        _supplier(
          models: const <CodexSupplierModelEntry>[
            CodexSupplierModelEntry(id: 'a', enabled: true),
            CodexSupplierModelEntry(id: 'b', enabled: true),
            CodexSupplierModelEntry(id: 'c', enabled: false),
          ],
          activeModelId: 'a',
        ),
      );

      await CodexSupplierStore.setVisibleModelsEnabled(
        supplierId: 'sup-a',
        visibleModelIds: const <String>['a', 'b'],
        enabled: false,
      );
      var lib = CodexSupplierStore.read().find('sup-a')!;
      expect(lib.models.where((m) => m.id == 'a').single.enabled, isFalse);
      expect(lib.models.where((m) => m.id == 'b').single.enabled, isFalse);

      await CodexSupplierStore.invertVisibleModels(
        supplierId: 'sup-a',
        visibleModelIds: const <String>['a', 'c'],
      );
      lib = CodexSupplierStore.read().find('sup-a')!;
      expect(lib.models.where((m) => m.id == 'a').single.enabled, isTrue);
      expect(lib.models.where((m) => m.id == 'c').single.enabled, isTrue);
    });

    test('addManualModel defaults enabled', () async {
      await CodexSupplierStore.upsert(
        _supplier(
          models: const <CodexSupplierModelEntry>[
            CodexSupplierModelEntry(id: 'keep', enabled: true),
          ],
          activeModelId: 'keep',
        ),
      );
      final next = await CodexSupplierStore.addManualModel(
        supplierId: 'sup-a',
        modelId: 'hand-id',
      );
      expect(
        next.models.where((m) => m.id == 'hand-id').single.enabled,
        isTrue,
      );
    });
  });
}
