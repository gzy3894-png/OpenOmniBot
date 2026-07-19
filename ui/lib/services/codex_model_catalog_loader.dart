import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/model_provider_config_service.dart';

typedef CodexLocalConfigReader = Future<CodexLocalConfig> Function();
typedef CodexProviderHttpModelReader =
    Future<CodexHttpModelsResult> Function({
      required String baseUrl,
      required String apiKey,
    });
typedef CodexAppServerModelReader =
    Future<Map<String, dynamic>> Function();
typedef CodexRunConfigReader = Future<Map<String, dynamic>> Function();
typedef CodexActiveProviderIdReader = Future<String> Function();
typedef CodexProviderProfileReader =
    Future<ModelProviderProfileSummary?> Function({
      required String providerId,
    });
typedef CodexManualProviderModelReader =
    Future<List<String>> Function({required String providerId});
typedef CodexCachedProviderModelReader =
    Future<List<ProviderModelOption>> Function({
      required String providerId,
      required String apiBase,
    });
typedef CodexProviderModelCacheWriter =
    Future<void> Function({
      required String providerId,
      required String apiBase,
      required List<ProviderModelOption> models,
    });

/// Fetches the Codex model catalog from the source owned by the active runtime.
///
/// Local runtimes merge the active supplier's explicit manual ids with its
/// fresh HTTP catalog, falling back to that same supplier's base-scoped cache.
/// App-server remains optional effort metadata unless no supplier library is
/// available. Remote runtimes never inspect the phone's local provider base URL
/// or API key; their app-server catalog is authoritative.
class CodexModelCatalogLoader {
  CodexModelCatalogLoader({
    CodexLocalConfigReader? readLocalConfig,
    CodexProviderHttpModelReader? readProviderHttpModels,
    CodexAppServerModelReader? readAppServerModels,
    CodexRunConfigReader? readRunConfig,
    CodexActiveProviderIdReader? readActiveProviderId,
    CodexProviderProfileReader? readProviderProfile,
    CodexManualProviderModelReader? readManualProviderModels,
    CodexCachedProviderModelReader? readCachedProviderModels,
    CodexProviderModelCacheWriter? writeCachedProviderModels,
  }) : _readLocalConfig =
           readLocalConfig ?? CodexAppServerService.readLocalConfig,
       _readProviderHttpModels =
           readProviderHttpModels ?? _defaultReadProviderHttpModels,
       _readAppServerModels =
           readAppServerModels ?? CodexAppServerService.listModels,
       _readRunConfig = readRunConfig ?? CodexAppServerService.readConfig,
       _readActiveProviderId =
           readActiveProviderId ?? _defaultReadActiveProviderId,
       _readProviderProfile =
           readProviderProfile ?? _defaultReadProviderProfile,
       _readManualProviderModels =
           readManualProviderModels ?? _defaultReadManualProviderModels,
       _readCachedProviderModels =
           readCachedProviderModels ?? _defaultReadCachedProviderModels,
       _writeCachedProviderModels =
           writeCachedProviderModels ?? _defaultWriteCachedProviderModels;

  final CodexLocalConfigReader _readLocalConfig;
  final CodexProviderHttpModelReader _readProviderHttpModels;
  final CodexAppServerModelReader _readAppServerModels;
  final CodexRunConfigReader _readRunConfig;
  final CodexActiveProviderIdReader _readActiveProviderId;
  final CodexProviderProfileReader _readProviderProfile;
  final CodexManualProviderModelReader _readManualProviderModels;
  final CodexCachedProviderModelReader _readCachedProviderModels;
  final CodexProviderModelCacheWriter _writeCachedProviderModels;

  static Future<CodexHttpModelsResult> _defaultReadProviderHttpModels({
    required String baseUrl,
    required String apiKey,
  }) {
    return CodexAppServerService.listModelsFromProviderHttp(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
  }

  static Future<String> _defaultReadActiveProviderId() async {
    try {
      return ModelProviderConfigService
          .readCodexProviderState()
          .activeProviderId;
    } catch (_) {
      return '';
    }
  }

  static Future<ModelProviderProfileSummary?> _defaultReadProviderProfile({
    required String providerId,
  }) async {
    final normalizedId = providerId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    final payload = await ModelProviderConfigService.listProfiles();
    for (final profile in payload.profiles) {
      if (profile.id == normalizedId) {
        return profile;
      }
    }
    return null;
  }

  static Future<List<String>> _defaultReadManualProviderModels({
    required String providerId,
  }) {
    return ModelProviderConfigService.getManualModelIds(
      profileId: providerId,
    );
  }

  static Future<List<ProviderModelOption>> _defaultReadCachedProviderModels({
    required String providerId,
    required String apiBase,
  }) {
    return ModelProviderConfigService.getCachedFetchedModels(
      profileId: providerId,
      apiBase: apiBase,
    );
  }

  static Future<void> _defaultWriteCachedProviderModels({
    required String providerId,
    required String apiBase,
    required List<ProviderModelOption> models,
  }) {
    return ModelProviderConfigService.saveCachedFetchedModels(
      profileId: providerId,
      apiBase: apiBase,
      models: models,
    );
  }

  Future<_CodexLocalProviderBinding?> _resolveProviderBinding({
    required String providerId,
    required CodexLocalConfig localConfig,
  }) async {
    final normalizedId = providerId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    final profile = await _readProviderProfile(providerId: normalizedId);
    if (profile == null || profile.id != normalizedId) {
      return null;
    }
    final profileBase = ModelProviderConfigService.normalizeApiBase(
      profile.baseUrl,
    );
    final nativeBase = ModelProviderConfigService.normalizeApiBase(
      localConfig.baseUrl,
    );
    final profileKey = profile.apiKey.trim();
    final nativeKey = localConfig.apiKey.trim();
    if (profileBase == null ||
        nativeBase == null ||
        profileBase != nativeBase ||
        profileKey.isEmpty ||
        profileKey != nativeKey) {
      return null;
    }
    return _CodexLocalProviderBinding(
      providerId: normalizedId,
      apiBase: profileBase,
      apiKey: profileKey,
    );
  }

  Future<bool> _isProviderBindingCurrent(
    _CodexLocalProviderBinding expected,
  ) async {
    try {
      final currentProviderId = (await _readActiveProviderId()).trim();
      if (currentProviderId != expected.providerId) {
        return false;
      }
      final currentConfig = await _readLocalConfig();
      final current = await _resolveProviderBinding(
        providerId: currentProviderId,
        localConfig: currentConfig,
      );
      return current != null && current.sameIdentity(expected);
    } catch (_) {
      return false;
    }
  }

  Future<void> _requireProviderBindingCurrent(
    _CodexLocalProviderBinding binding,
  ) async {
    if (!await _isProviderBindingCurrent(binding)) {
      throw StateError(
        'Codex provider identity changed while loading models',
      );
    }
  }

  Future<CodexModelCatalogSourceResult> load({
    required bool remoteRuntime,
  }) async {
    if (remoteRuntime) {
      final appServerResponse = await _readAppServerModels();
      return CodexModelCatalogSourceResult(
        source: 'app_server_remote',
        appServerResponse: appServerResponse,
        useAppServerModelIds: true,
        providerIdentity: 'remote',
      );
    }

    Map<String, dynamic> runConfigResponse = const <String, dynamic>{};
    Object? runConfigError;
    try {
      runConfigResponse = await _readRunConfig();
    } catch (error) {
      runConfigError = error;
    }

    var activeProviderId = '';
    try {
      activeProviderId = (await _readActiveProviderId()).trim();
    } catch (_) {
      // Runtime config remains usable while application selection recovers.
    }

    CodexLocalConfig? localConfig;
    Object? httpError;
    try {
      localConfig = await _readLocalConfig();
    } catch (error) {
      httpError = error;
    }

    _CodexLocalProviderBinding? providerBinding;
    if (activeProviderId.isNotEmpty) {
      if (localConfig == null) {
        throw StateError(
          'Codex provider identity is not bound to native configuration',
        );
      }
      providerBinding = await _resolveProviderBinding(
        providerId: activeProviderId,
        localConfig: localConfig,
      );
      if (providerBinding == null) {
        throw StateError(
          'Codex provider identity is not bound to native configuration',
        );
      }
      await _requireProviderBindingCurrent(providerBinding);
    }

    var manualModelIds = const <String>[];
    if (providerBinding != null) {
      try {
        manualModelIds = await _readManualProviderModels(
          providerId: providerBinding.providerId,
        );
      } catch (_) {
        // A storage failure must not hide the provider's live catalog.
      }
      await _requireProviderBindingCurrent(providerBinding);
    }

    CodexHttpModelsResult? httpResult;
    if (localConfig != null) {
      try {
        httpResult = await _readProviderHttpModels(
          baseUrl: localConfig.baseUrl,
          apiKey: localConfig.apiKey,
        );
      } catch (error) {
        httpError = error;
      }
    }

    if (httpResult == null) {
      var storedModels = const <ProviderModelOption>[];
      if (providerBinding != null) {
        await _requireProviderBindingCurrent(providerBinding);
        var cachedModels = const <ProviderModelOption>[];
        try {
          cachedModels = await _readCachedProviderModels(
            providerId: providerBinding.providerId,
            apiBase: providerBinding.apiBase,
          );
        } catch (_) {
          // Manual ids remain usable if the fetched-model cache is unreadable.
        }
        await _requireProviderBindingCurrent(providerBinding);
        storedModels = ModelProviderConfigService.mergeModelOptions(
          remoteModels: cachedModels,
          manualModelIds: manualModelIds,
        );
        await _requireProviderBindingCurrent(providerBinding);
      }
      if (storedModels.isNotEmpty) {
        Map<String, dynamic> appServerResponse = const <String, dynamic>{};
        Object? metadataError;
        try {
          appServerResponse = await _readAppServerModels();
        } catch (error) {
          metadataError = error;
        }
        if (providerBinding != null) {
          await _requireProviderBindingCurrent(providerBinding);
        }
        return CodexModelCatalogSourceResult(
          source: 'provider_library_cache',
          appServerResponse: appServerResponse,
          useAppServerModelIds: false,
          providerModelIds:
              storedModels.map((item) => item.id).toList(growable: false),
          httpError: httpError,
          metadataError: metadataError,
          providerIdentity: _localProviderIdentity(
            localConfig,
            providerBinding: providerBinding,
          ),
          runConfigResponse: runConfigResponse,
          runConfigError: runConfigError,
        );
      }
      final appServerResponse = await _readAppServerModels();
      if (providerBinding != null) {
        await _requireProviderBindingCurrent(providerBinding);
      }
      return CodexModelCatalogSourceResult(
        source: 'app_server_fallback',
        appServerResponse: appServerResponse,
        useAppServerModelIds: true,
        httpError: httpError,
        providerIdentity: _localProviderIdentity(
          localConfig,
          providerBinding: providerBinding,
        ),
        runConfigResponse: runConfigResponse,
        runConfigError: runConfigError,
      );
    }

    Map<String, dynamic> appServerResponse = const <String, dynamic>{};
    Object? metadataError;
    try {
      appServerResponse = await _readAppServerModels();
    } catch (error) {
      // Provider HTTP already succeeded, including an explicit data: [].
      // app-server is optional here because it may only enrich effort metadata.
      metadataError = error;
    }
    final freshRemoteModels = httpResult.modelIds
        .map(
          (id) => ProviderModelOption(
            id: id,
            displayName: id,
            ownedBy: 'remote',
          ),
        )
        .toList(growable: false);
    if (providerBinding != null) {
      await _requireProviderBindingCurrent(providerBinding);
      try {
        await _writeCachedProviderModels(
          providerId: providerBinding.providerId,
          apiBase: providerBinding.apiBase,
          models: freshRemoteModels,
        );
      } catch (_) {
        // The live result remains authoritative if its scoped cache cannot update.
      }
      await _requireProviderBindingCurrent(providerBinding);
    }
    final providerModels = ModelProviderConfigService.mergeModelOptions(
      remoteModels: freshRemoteModels,
      manualModelIds: manualModelIds,
    );
    if (providerBinding != null) {
      await _requireProviderBindingCurrent(providerBinding);
    }
    return CodexModelCatalogSourceResult(
      source: httpResult.source,
      httpResult: httpResult,
      appServerResponse: appServerResponse,
      useAppServerModelIds: false,
      providerModelIds:
          providerModels.map((item) => item.id).toList(growable: false),
      metadataError: metadataError,
      providerIdentity: _localProviderIdentity(
        localConfig,
        providerBinding: providerBinding,
      ),
      runConfigResponse: runConfigResponse,
      runConfigError: runConfigError,
    );
  }
}

class _CodexLocalProviderBinding {
  const _CodexLocalProviderBinding({
    required this.providerId,
    required this.apiBase,
    required this.apiKey,
  });

  final String providerId;
  final String apiBase;
  final String apiKey;

  bool sameIdentity(_CodexLocalProviderBinding other) {
    return providerId == other.providerId &&
        apiBase == other.apiBase &&
        apiKey == other.apiKey;
  }
}

class CodexModelCatalogSourceResult {
  const CodexModelCatalogSourceResult({
    required this.source,
    required this.appServerResponse,
    required this.useAppServerModelIds,
    required this.providerIdentity,
    this.providerModelIds = const <String>[],
    this.httpResult,
    this.httpError,
    this.metadataError,
    this.runConfigResponse = const <String, dynamic>{},
    this.runConfigError,
  });

  final String source;
  final CodexHttpModelsResult? httpResult;
  final Map<String, dynamic> appServerResponse;
  final bool useAppServerModelIds;
  final List<String> providerModelIds;
  final String providerIdentity;
  final Object? httpError;
  final Object? metadataError;
  final Map<String, dynamic> runConfigResponse;
  final Object? runConfigError;

  bool get providerHttpSucceeded => httpResult != null;
}

/// Monotonic request gate used by the UI so slower provider/runtime requests
/// cannot overwrite a later configuration.
class CodexModelCatalogRequestGate {
  int _generation = 0;

  int get generation => _generation;

  CodexModelCatalogRequestToken begin({required String runtimeIdentity}) {
    _generation += 1;
    return CodexModelCatalogRequestToken(
      generation: _generation,
      runtimeIdentity: runtimeIdentity,
    );
  }

  void invalidate() {
    _generation += 1;
  }

  bool isCurrent(
    CodexModelCatalogRequestToken token, {
    required String runtimeIdentity,
  }) {
    return token.generation == _generation &&
        token.runtimeIdentity == runtimeIdentity;
  }
}

class CodexModelCatalogRequestToken {
  const CodexModelCatalogRequestToken({
    required this.generation,
    required this.runtimeIdentity,
  });

  final int generation;
  final String runtimeIdentity;
}

String codexModelRuntimeIdentity(CodexStatus status) {
  final runtime = status.runtime?.trim().toLowerCase() ?? '';
  final remote = status.remoteEnabled || runtime == 'remote';
  final generation = status.sessionGeneration;
  final sessionSuffix = generation == null ? '' : '|session=$generation';
  if (remote) {
    final bridge = status.remoteBridgeUrl?.trim() ?? '';
    final identity = bridge.isEmpty ? 'remote' : 'remote:$bridge';
    return '$identity$sessionSuffix';
  }
  final home = status.codexHome?.trim() ?? '';
  final identity = home.isEmpty ? 'local' : 'local:$home';
  return '$identity$sessionSuffix';
}

String _localProviderIdentity(
  CodexLocalConfig? config, {
  required _CodexLocalProviderBinding? providerBinding,
}) {
  if (providerBinding != null) {
    return 'local:provider=${providerBinding.providerId}';
  }
  if (config == null) {
    return 'local:unavailable';
  }
  final baseUrl = config.baseUrl.trim();
  return 'local:$baseUrl';
}
