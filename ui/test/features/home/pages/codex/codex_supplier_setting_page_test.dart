import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/home/pages/codex/codex_supplier_setting_page.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_supplier_store.dart';
import 'package:ui/services/storage_service.dart';
import 'package:ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.init();
    CodexSupplierStore.debugResetMemory();
    CodexSupplierStore.debugSetMigrateHook(() async {});
    await StorageService.setBool(CodexSupplierStore.migrationFlagKey, true);
  });

  tearDown(() {
    CodexSupplierStore.debugSetMigrateHook(null);
    CodexSupplierStore.debugResetMemory();
  });

  Future<void> seedSupplier({
    String id = 'codex-supplier-test-1',
    List<CodexSupplierModelEntry> models = const <CodexSupplierModelEntry>[],
  }) async {
    await CodexSupplierStore.write(
      CodexSupplierLibrary(
        activeSupplierId: id,
        suppliers: <CodexSupplierRecord>[
          CodexSupplierRecord(
            id: id,
            memoName: 'Demo 中转',
            baseUrl: 'https://api.example.com/v1',
            apiKey: 'sk-secret-should-not-appear',
            models: models,
            activeModelId: models.isEmpty
                ? ''
                : models.firstWhere(
                    (item) => item.enabled,
                    orElse: () => models.first,
                  ).id,
            activeEffort: 'medium',
            updatedAt: 1,
          ),
        ],
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Future<CodexHttpModelsResult> Function({
      required String baseUrl,
      required String apiKey,
    })?
    listModelsOverride,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: CodexSupplierSettingPage(
          listModelsOverride: listModelsOverride,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders supplier page without protocol selector', (
    tester,
  ) async {
    await seedSupplier(
      models: const <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'gpt-4.1', enabled: true),
        CodexSupplierModelEntry(id: 'o3', enabled: false),
      ],
    );

    await pumpPage(tester);

    expect(find.byKey(const Key('codex-supplier-setting-page')), findsOneWidget);
    expect(find.byKey(const Key('codex-supplier-wire-locked')), findsOneWidget);
    expect(find.textContaining('wire_api = responses'), findsWidgets);
    expect(find.text('Chat Completions'), findsNothing);
    expect(find.text('chat_completions'), findsNothing);
    expect(find.text('模型类型'), findsNothing);

    expect(find.text('Demo 中转'), findsWidgets);
    expect(find.byKey(const Key('codex-supplier-base-url-field')), findsOneWidget);
    expect(find.byKey(const Key('codex-supplier-api-key-field')), findsOneWidget);
    expect(find.byKey(const Key('codex-supplier-memo-field')), findsOneWidget);

    // Key must not leak into debug/status text.
    expect(find.textContaining('sk-secret-should-not-appear'), findsNothing);
    expect(find.textContaining('启用 1 / 可见 2 / 总数 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters models case-insensitively', (tester) async {
    await seedSupplier(
      models: const <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'gpt-4.1', enabled: true),
        CodexSupplierModelEntry(id: 'GPT-4o-mini', enabled: true),
        CodexSupplierModelEntry(id: 'o3-pro', enabled: true),
      ],
    );

    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('codex-supplier-model-search')),
      'gpt',
    );
    await tester.pump();

    expect(find.byKey(const Key('codex-supplier-model-gpt-4.1')), findsOneWidget);
    expect(
      find.byKey(const Key('codex-supplier-model-GPT-4o-mini')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('codex-supplier-model-o3-pro')), findsNothing);
    expect(find.textContaining('可见 2'), findsOneWidget);
  });

  testWidgets('select visible enables only the filtered set', (tester) async {
    await seedSupplier(
      models: const <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'alpha', enabled: false),
        CodexSupplierModelEntry(id: 'beta', enabled: false),
        CodexSupplierModelEntry(id: 'gamma', enabled: true),
      ],
    );

    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('codex-supplier-model-search')),
      'a',
    );
    await tester.pump();
    // visible: alpha, gamma (beta filtered out)
    await tester.tap(find.byKey(const Key('codex-supplier-select-visible')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final library = CodexSupplierStore.read();
    final models = library.suppliers.single.models;
    bool enabledOf(String id) =>
        models.firstWhere((item) => item.id == id).enabled;
    expect(enabledOf('alpha'), isTrue);
    expect(enabledOf('beta'), isFalse);
    expect(enabledOf('gamma'), isTrue);
  });

  testWidgets('fetch models merges with default-enable new ids', (
    tester,
  ) async {
    await seedSupplier(
      models: const <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'keep-me', enabled: false),
      ],
    );

    await pumpPage(
      tester,
      listModelsOverride: ({
        required String baseUrl,
        required String apiKey,
      }) async {
        expect(baseUrl, contains('api.example.com'));
        // Override still receives key; page must not paint it.
        expect(apiKey, isNotEmpty);
        return const CodexHttpModelsResult(
          modelIds: <String>['keep-me', 'new-model-a', 'new-model-b'],
          endpoint: 'https://api.example.com/v1/models',
          statusCode: 200,
        );
      },
    );

    await tester.tap(find.byKey(const Key('codex-supplier-fetch-models')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final library = CodexSupplierStore.read();
    final models = library.suppliers.single.models;
    final byId = <String, CodexSupplierModelEntry>{
      for (final model in models) model.id: model,
    };
    expect(byId['keep-me']!.enabled, isFalse); // preserve user choice
    expect(byId['new-model-a']!.enabled, isTrue);
    expect(byId['new-model-b']!.enabled, isTrue);
    expect(find.textContaining('sk-secret-should-not-appear'), findsNothing);
  });

  testWidgets('add supplier creates empty draft in Codex store only', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(CodexSupplierStore.read().suppliers, isEmpty);
    await tester.tap(find.byKey(const Key('codex-supplier-add-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final library = CodexSupplierStore.read();
    expect(library.suppliers, hasLength(1));
    expect(library.suppliers.single.baseUrl, isEmpty);
    expect(find.byKey(const Key('codex-supplier-form')), findsOneWidget);
    expect(find.text('Chat Completions'), findsNothing);
  });
}
