import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/codex/widgets/codex_provider_selector.dart';
import 'package:ui/services/codex_supplier_store.dart';

void main() {
  const suppliers = <CodexSupplierRecord>[
    CodexSupplierRecord(
      id: 's1',
      memoName: 'Alpha',
      baseUrl: 'https://example.com/v1',
      apiKey: 'k1',
      models: <CodexSupplierModelEntry>[
        CodexSupplierModelEntry(id: 'm1', enabled: true),
        CodexSupplierModelEntry(id: 'm2', enabled: false),
        CodexSupplierModelEntry(id: 'm3', enabled: true),
      ],
      activeModelId: 'm1',
      activeEffort: 'medium',
    ),
  ];

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  testWidgets('lists only enabled models and exposes effort selector', (
    tester,
  ) async {
    String? changedModel;
    String? changedEffort;

    await tester.pumpWidget(
      wrap(
        CodexProviderSelector(
          suppliers: suppliers,
          activeSupplierId: 's1',
          enabledModels: suppliers.first.enabledModels,
          activeModelId: 'm1',
          activeEffort: 'medium',
          busy: false,
          onSupplierChanged: (_) {},
          onModelChanged: (id) => changedModel = id,
          onEffortChanged: (effort) => changedEffort = effort,
          onManageSuppliers: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('codex-provider-selector')), findsOneWidget);
    expect(
      find.byKey(const Key('codex-provider-model-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('codex-provider-effort-selector')),
      findsOneWidget,
    );

    // Model dropdown contains only enabled ids.
    await tester.tap(find.byKey(const Key('codex-provider-model-selector')));
    await tester.pumpAndSettle();
    expect(find.text('m1').hitTestable(), findsWidgets);
    expect(find.text('m3').hitTestable(), findsOneWidget);
    expect(find.text('m2').hitTestable(), findsNothing);

    await tester.tap(find.text('m3').last);
    await tester.pumpAndSettle();
    expect(changedModel, 'm3');

    await tester.tap(find.byKey(const Key('codex-provider-effort-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('high').last);
    await tester.pumpAndSettle();
    expect(changedEffort, 'high');
  });

  testWidgets('disables model switch when no enabled models', (tester) async {
    var modelChanged = false;

    await tester.pumpWidget(
      wrap(
        CodexProviderSelector(
          suppliers: const <CodexSupplierRecord>[
            CodexSupplierRecord(
              id: 'empty',
              baseUrl: 'https://example.com/v1',
              apiKey: 'k',
              models: <CodexSupplierModelEntry>[
                CodexSupplierModelEntry(id: 'off', enabled: false),
              ],
            ),
          ],
          activeSupplierId: 'empty',
          enabledModels: const <CodexSupplierModelEntry>[],
          activeModelId: '',
          activeEffort: 'medium',
          busy: false,
          onSupplierChanged: (_) {},
          onModelChanged: (_) => modelChanged = true,
          onEffortChanged: (_) {},
          onManageSuppliers: () {},
        ),
      ),
    );

    final modelField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('codex-provider-model-selector')),
    );
    expect(modelField.onChanged, isNull);
    expect(modelChanged, isFalse);
    expect(
      find.textContaining('启用至少一个模型'),
      findsOneWidget,
    );
  });
}
