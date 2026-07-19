import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/models_dev_catalog_service.dart';
import 'package:ui/services/storage_service.dart';

const _modelsDevCatalogJson = '''
{
  "openai": {
    "id": "openai",
    "name": "OpenAI",
    "models": {
      "gpt-4o": {
        "id": "gpt-4o",
        "name": "GPT-4o",
        "limit": {"context": 128000, "input": 96000, "output": 16384},
        "modalities": {"input": ["text", "image", "pdf"], "output": ["text"]},
        "family": "gpt",
        "attachment": true,
        "reasoning": false,
        "tool_call": true,
        "structured_output": true,
        "temperature": true
      }
    }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ModelsDevCatalogService.resetForTesting);

  test('builds request urls from root base url', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl(
        'https://api.example.com',
      ),
      'https://api.example.com/v1/models',
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com',
      ),
      'https://api.example.com/v1/chat/completions',
    );
    expect(
      ModelProviderConfigService.buildResponsesRequestUrl(
        'https://api.example.com',
      ),
      'https://api.example.com/v1/responses',
    );
  });

  test('allows trailing marker to bypass automatic request suffixes', () {
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com/custom/chat#',
      ),
      'https://api.example.com/custom/chat',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.example.com/custom/messages#',
      ),
      'https://api.example.com/custom/messages',
    );
  });

  test('builds request urls without duplicating v1 suffix', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl(
        'https://api.example.com/v1',
      ),
      'https://api.example.com/v1/models',
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://api.example.com/v1',
      ),
      'https://api.example.com/v1/chat/completions',
    );
  });

  test('builds request urls for compatible-mode versioned base', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      'https://dashscope.aliyuncs.com/compatible-mode/v1/models',
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    );
    expect(
      ModelProviderConfigService.buildResponsesRequestUrl(
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ),
      'https://dashscope.aliyuncs.com/compatible-mode/v1/responses',
    );
  });

  test(
    'normalizes explicit endpoint inputs before rebuilding request urls',
    () {
      expect(
        ModelProviderConfigService.buildModelsRequestUrl(
          'https://api.example.com/v1/responses',
        ),
        'https://api.example.com/v1/models',
      );
      expect(
        ModelProviderConfigService.buildChatCompletionsRequestUrl(
          'https://api.example.com/v1/models',
        ),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        ModelProviderConfigService.buildResponsesRequestUrl(
          'https://api.example.com/v1/chat/completions',
        ),
        'https://api.example.com/v1/responses',
      );
    },
  );

  test('builds anthropic request urls from base url', () {
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com',
      ),
      'https://api.anthropic.com/v1/messages',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com/v1',
      ),
      'https://api.anthropic.com/v1/messages',
    );
    expect(
      ModelProviderConfigService.buildAnthropicMessagesRequestUrl(
        'https://api.anthropic.com/v1/messages',
      ),
      'https://api.anthropic.com/v1/messages',
    );
  });

  test('returns null for invalid base url input', () {
    expect(
      ModelProviderConfigService.buildModelsRequestUrl('api.example.com'),
      isNull,
    );
    expect(
      ModelProviderConfigService.buildChatCompletionsRequestUrl(''),
      isNull,
    );
  });

  test('infers responses wire api from explicit responses endpoint input', () {
    expect(
      ModelProviderConfigService.inferWireApi(
        'https://api.example.com/v1/responses',
      ),
      'responses',
    );
    expect(
      ModelProviderConfigService.inferWireApi(
        'https://api.example.com/responses#',
      ),
      'responses',
    );
    expect(
      ModelProviderConfigService.inferWireApi('https://api.example.com/v1'),
      'chat_completions',
    );
  });

  test('parses legacy cached model options without metadata', () {
    final option = ProviderModelOption.fromMap({
      'id': 'legacy-model',
      'displayName': 'Legacy Model',
      'ownedBy': 'remote',
    });

    expect(option.id, 'legacy-model');
    expect(option.displayName, 'Legacy Model');
    expect(option.contextLimit, isNull);
    expect(option.inputModalities, isEmpty);
  });

  test('enriches model options with models.dev metadata', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    ModelsDevCatalogService.setCatalogForTesting(
      ModelsDevCatalogService.parseCatalog(_modelsDevCatalogJson),
    );

    final enriched = await ModelProviderConfigService.enrichModelsForProfile(
      profileId: 'provider-1',
      providerName: 'OpenAI',
      apiBase: 'https://api.openai.com/v1',
      models: const [ProviderModelOption(id: 'gpt-4o', displayName: 'gpt-4o')],
    );

    expect(enriched.single.displayName, 'GPT-4o');
    expect(enriched.single.contextLimit, 128000);
    expect(enriched.single.inputLimit, 96000);
    expect(enriched.single.outputLimit, 16384);
    expect(enriched.single.inputModalities, ['text', 'image', 'pdf']);
    expect(enriched.single.outputModalities, ['text']);
    expect(enriched.single.attachment, isTrue);
    expect(enriched.single.toolCall, isTrue);
    expect(enriched.single.structuredOutput, isTrue);
    expect(enriched.single.temperature, isTrue);
    expect(
      enriched.single.providerLogoUrl,
      'https://models.dev/logos/openai.svg',
    );
    expect(enriched.single.group, 'openai');
  });

  test('keeps remote limit metadata when catalog fallback is lower', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    ModelsDevCatalogService.setCatalogForTesting(
      ModelsDevCatalogService.parseCatalog(_modelsDevCatalogJson),
    );

    final enriched = await ModelProviderConfigService.enrichModelsForProfile(
      profileId: 'provider-1',
      providerName: 'OpenAI',
      apiBase: 'https://api.openai.com/v1',
      models: const [
        ProviderModelOption(
          id: 'gpt-4o',
          displayName: 'gpt-4o',
          contextLimit: 1000000,
          inputLimit: 800000,
          outputLimit: 32000,
          toolCall: false,
        ),
      ],
    );

    expect(enriched.single.contextLimit, 1000000);
    expect(enriched.single.inputLimit, 800000);
    expect(enriched.single.outputLimit, 32000);
    expect(enriched.single.toolCall, isFalse);
  });

  test(
    'enriches common model ids even when provider is a custom proxy',
    () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.init();
      ModelsDevCatalogService.setCatalogForTesting(
        ModelsDevCatalogService.parseCatalog(_modelsDevCatalogJson),
      );

      final enriched = await ModelProviderConfigService.enrichModelsForProfile(
        profileId: 'custom-proxy',
        providerName: 'My Proxy',
        apiBase: 'https://llm.example.com/v1',
        models: const [
          ProviderModelOption(id: 'openai/gpt-4o:free', displayName: 'gpt-4o'),
        ],
      );

      expect(enriched.single.contextLimit, 128000);
      expect(enriched.single.modelsDevProviderId, 'openai');
      expect(
        enriched.single.providerLogoUrl,
        'https://models.dev/logos/openai.svg',
      );
      expect(enriched.single.toolCall, isTrue);
    },
  );

  test('filters chat model options by hidden ids and defaults to visible', () {
    const models = [
      ProviderModelOption(id: 'gpt-4o', displayName: 'GPT-4o'),
      ProviderModelOption(id: 'gpt-4o-mini', displayName: 'GPT-4o mini'),
    ];

    expect(
      ModelProviderConfigService.filterChatModelOptions(
        models: models,
        hiddenModelIds: const [],
      ).map((item) => item.id),
      ['gpt-4o', 'gpt-4o-mini'],
    );
    expect(
      ModelProviderConfigService.filterChatModelOptions(
        models: models,
        hiddenModelIds: const ['gpt-4o-mini', 'missing', 'gpt-4o-mini'],
      ).map((item) => item.id),
      ['gpt-4o'],
    );
  });

  test('Codex supplier state keys models by stable id, not memo name', () {
    final state = const CodexProviderState().selecting(
      providerId: 'provider-a',
      modelId: 'model-a',
    ).selecting(providerId: 'provider-b', modelId: 'model-b');
    final restored = CodexProviderState.fromMap(state.toMap());

    expect(restored.activeProviderId, 'provider-b');
    expect(restored.currentModels, {
      'provider-a': 'model-a',
      'provider-b': 'model-b',
    });
    expect(restored.toMap().toString(), isNot(contains('Provider memo')));
  });

  test('Codex compatibility rejects non-Responses suppliers with a reason', () {
    const supported = ModelProviderProfileSummary(
      id: 'provider-a',
      name: 'Memo A',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'secret',
      customHeaders: {},
      sourceType: 'custom',
      readOnly: false,
      ready: true,
      statusText: '',
      configured: true,
      wireApi: 'responses',
    );
    const unsupported = ModelProviderProfileSummary(
      id: 'provider-b',
      name: 'Memo B',
      baseUrl: 'https://api.example.com/v1',
      apiKey: 'secret',
      customHeaders: {},
      sourceType: 'custom',
      readOnly: false,
      ready: true,
      statusText: '',
      configured: true,
      wireApi: 'chat_completions',
    );

    expect(
      ModelProviderConfigService.codexCompatibility(supported).isSupported,
      isTrue,
    );
    expect(
      ModelProviderConfigService.codexCompatibility(unsupported).reason,
      contains('Responses'),
    );
  });

  test('Codex compatibility rejects direct or query endpoint URLs', () {
    ModelProviderProfileSummary profile(String baseUrl) {
      return ModelProviderProfileSummary(
        id: 'provider-a',
        name: 'Memo A',
        baseUrl: baseUrl,
        apiKey: 'secret',
        customHeaders: const {},
        sourceType: 'custom',
        readOnly: false,
        ready: true,
        statusText: '',
        configured: true,
        wireApi: 'responses',
      );
    }

    expect(
      ModelProviderConfigService.codexCompatibility(
        profile('https://api.example.com/v1/responses#'),
      ).isSupported,
      isFalse,
    );
    expect(
      ModelProviderConfigService.codexCompatibility(
        profile('https://api.example.com/v1?token=hidden'),
      ).isSupported,
      isFalse,
    );
  });

  test('manual Codex model libraries remain isolated per supplier id', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await ModelProviderConfigService.saveManualModelIds(
      profileId: 'provider-a',
      ids: const ['model-a'],
    );
    await ModelProviderConfigService.saveManualModelIds(
      profileId: 'provider-b',
      ids: const ['model-b'],
    );

    expect(
      await ModelProviderConfigService.getManualModelIds(
        profileId: 'provider-a',
      ),
      ['model-a'],
    );
    expect(
      await ModelProviderConfigService.getManualModelIds(
        profileId: 'provider-b',
      ),
      ['model-b'],
    );
  });

  test('supplier cache is invalidated when the same id changes API base', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    await ModelProviderConfigService.saveCachedFetchedModels(
      profileId: 'provider-a',
      apiBase: 'https://old.example/v1',
      models: const <ProviderModelOption>[
        ProviderModelOption(id: 'old-model', displayName: 'old-model'),
      ],
    );

    expect(
      (await ModelProviderConfigService.getCachedFetchedModels(
        profileId: 'provider-a',
        apiBase: 'https://old.example/v1',
      )).map((item) => item.id),
      ['old-model'],
    );
    expect(
      await ModelProviderConfigService.getCachedFetchedModels(
        profileId: 'provider-a',
        apiBase: 'https://new.example/v1',
      ),
      isEmpty,
    );
  });

  test('committing a Codex supplier selection publishes a revision', () async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();
    final revisionBefore =
        ModelProviderConfigService.codexProviderStateRevision.value;
    var notifications = 0;
    void onRevision() {
      notifications += 1;
    }

    ModelProviderConfigService.codexProviderStateRevision.addListener(
      onRevision,
    );
    try {
      await ModelProviderConfigService.commitCodexProviderState(
        const CodexProviderState(
          activeProviderId: 'provider-b',
          currentModels: {'provider-b': 'model-b'},
        ),
      );
    } finally {
      ModelProviderConfigService.codexProviderStateRevision.removeListener(
        onRevision,
      );
    }

    expect(notifications, 1);
    expect(
      ModelProviderConfigService.codexProviderStateRevision.value,
      revisionBefore + 1,
    );
    expect(
      ModelProviderConfigService.readCodexProviderState().activeProviderId,
      'provider-b',
    );
  });
}
