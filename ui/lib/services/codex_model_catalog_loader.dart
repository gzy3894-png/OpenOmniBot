import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_supplier_store.dart';
import 'package:ui/services/model_provider_config_service.dart';

typedef CodexProviderHttpModelReader =
    Future<CodexHttpModelsResult> Function({
      required String baseUrl,
      required String apiKey,
    });
typedef CodexAppServerModelReader = Future<Map<String, dynamic>> Function();
typedef CodexRunConfigReader = Future<Map<String, dynamic>> Function();

/// Reads the active Codex supplier (application library, not Agent profiles).
typedef CodexActiveSupplierReader = Future<CodexSupplierRecord?> Function();

/// Merges remote `/models` ids into the Codex supplier library.
///
/// New ids default to enabled; existing enabled flags are preserved by the store.
typedef CodexSupplierMergeFetchedWriter =
    Future<CodexSupplierRecord> Function({
      required String supplierId,
      required List<String> remoteModelIds,
      bool defaultEnableNew,
    });

/// Fetches the Codex model catalog from the source owned by the active runtime.
///
/// Local runtimes treat the active [CodexSupplierStore] supplier's **enabled**
/// models as the authoritative id list. Background `GET {base}/models` may
/// merge fresh ids into that private library (new ids default enabled). HTTP
/// failure keeps the library as-is and never falls back to Agent
/// `ModelProviderConfigService` profile/cache paths. App-server `model/list`
/// remains optional effort metadata only and must not inject foreign ids into
/// the supplier library. Remote runtimes never inspect the phone's local
/// supplier credentials; their app-server catalog is authoritative.
class CodexModelCatalogLoader {
  CodexModelCatalogLoader({
    CodexProviderHttpModelReader? readProviderHttpModels,
    CodexAppServerModelReader? readAppServerModels,
    CodexRunConfigReader? readRunConfig,
    CodexActiveSupplierReader? readActiveSupplier,
    CodexSupplierMergeFetchedWriter? mergeFetchedModels,
  }) : _readProviderHttpModels =
           readProviderHttpModels ?? _defaultReadProviderHttpModels,
       _readAppServerModels =
           readAppServerModels ?? CodexAppServerService.listModels,
       _readRunConfig = readRunConfig ?? CodexAppServerService.readConfig,
       _readActiveSupplier =
           readActiveSupplier ?? _defaultReadActiveSupplier,
       _mergeFetchedModels =
           mergeFetchedModels ?? _defaultMergeFetchedModels;

  final CodexProviderHttpModelReader _readProviderHttpModels;
  final CodexAppServerModelReader _readAppServerModels;
  final CodexRunConfigReader _readRunConfig;
  final CodexActiveSupplierReader _readActiveSupplier;
  final CodexSupplierMergeFetchedWriter _mergeFetchedModels;

  static Future<CodexHttpModelsResult> _defaultReadProviderHttpModels({
    required String baseUrl,
    required String apiKey,
  }) {
    return CodexAppServerService.listModelsFromProviderHttp(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
  }

  static Future<CodexSupplierRecord?> _defaultReadActiveSupplier() async {
    try {
      return CodexSupplierStore.read().activeSupplier;
    } catch (_) {
      return null;
    }
  }

  static Future<CodexSupplierRecord> _defaultMergeFetchedModels({
    required String supplierId,
    required List<String> remoteModelIds,
    bool defaultEnableNew = true,
  }) {
    return CodexSupplierStore.mergeFetchedModels(
      supplierId: supplierId,
      remoteModelIds: remoteModelIds,
      defaultEnableNew: defaultEnableNew,
    );
  }

  Future<_CodexSupplierBinding?> _resolveActiveBinding() async {
    final supplier = await _readActiveSupplier();
    if (supplier == null) {
      return null;
    }
    final supplierId = supplier.id.trim();
    if (supplierId.isEmpty) {
      return null;
    }
    final apiBase =
        ModelProviderConfigService.normalizeApiBase(supplier.baseUrl) ??
        supplier.baseUrl.trim();
    final apiKey = supplier.apiKey.trim();
    return _CodexSupplierBinding(
      supplierId: supplierId,
      apiBase: apiBase,
      apiKey: apiKey,
      enabledModelIds: List<String>.from(supplier.enabledModelIds),
    );
  }

  Future<bool> _isSupplierBindingCurrent(_CodexSupplierBinding expected) async {
    try {
      final current = await _resolveActiveBinding();
      return current != null && current.sameIdentity(expected);
    } catch (_) {
      return false;
    }
  }

  Future<void> _requireSupplierBindingCurrent(
    _CodexSupplierBinding binding,
  ) async {
    if (!await _isSupplierBindingCurrent(binding)) {
      throw StateError(
        'Codex supplier identity changed while loading models',
      );
    }
  }

  Future<List<String>> _enabledIdsForBinding(
    _CodexSupplierBinding binding,
  ) async {
    await _requireSupplierBindingCurrent(binding);
    final supplier = await _readActiveSupplier();
    if (supplier == null || supplier.id.trim() != binding.supplierId) {
      throw StateError(
        'Codex supplier identity changed while loading models',
      );
    }
    return List<String>.from(supplier.enabledModelIds);
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

    final binding = await _resolveActiveBinding();
    if (binding == null) {
      // No Codex supplier library yet — optional app-server view only.
      final appServerResponse = await _readAppServerModels();
      return CodexModelCatalogSourceResult(
        source: 'app_server_fallback',
        appServerResponse: appServerResponse,
        useAppServerModelIds: true,
        providerIdentity: 'local:unavailable',
        runConfigResponse: runConfigResponse,
        runConfigError: runConfigError,
      );
    }

    await _requireSupplierBindingCurrent(binding);

    Object? httpError;
    CodexHttpModelsResult? httpResult;
    if (binding.apiBase.isNotEmpty && binding.apiKey.isNotEmpty) {
      try {
        httpResult = await _readProviderHttpModels(
          baseUrl: binding.apiBase,
          apiKey: binding.apiKey,
        );
      } catch (error) {
        httpError = error;
      }
    }

    if (httpResult != null) {
      await _requireSupplierBindingCurrent(binding);
      try {
        await _mergeFetchedModels(
          supplierId: binding.supplierId,
          remoteModelIds: httpResult.modelIds,
          defaultEnableNew: true,
        );
      } catch (_) {
        // Live HTTP ids still feed the result via re-read of enabled set;
        // a store write failure must not invent Agent-library fallbacks.
      }
    }

    final enabledModelIds = await _enabledIdsForBinding(binding);

    Map<String, dynamic> appServerResponse = const <String, dynamic>{};
    Object? metadataError;
    try {
      appServerResponse = await _readAppServerModels();
    } catch (error) {
      // app-server is optional: effort metadata only, never model-id truth.
      metadataError = error;
    }
    await _requireSupplierBindingCurrent(binding);

    final String source;
    if (httpResult != null) {
      source = httpResult.source;
    } else {
      // HTTP failed or was skipped: keep Codex supplier library enabled ids.
      // Never emit Agent-era `provider_library_cache`.
      source = 'codex_supplier_library';
    }

    return CodexModelCatalogSourceResult(
      source: source,
      httpResult: httpResult,
      appServerResponse: appServerResponse,
      useAppServerModelIds: false,
      providerModelIds: enabledModelIds,
      httpError: httpError,
      metadataError: metadataError,
      providerIdentity: 'local:provider=${binding.supplierId}',
      runConfigResponse: runConfigResponse,
      runConfigError: runConfigError,
    );
  }
}

class _CodexSupplierBinding {
  const _CodexSupplierBinding({
    required this.supplierId,
    required this.apiBase,
    required this.apiKey,
    required this.enabledModelIds,
  });

  final String supplierId;
  final String apiBase;
  final String apiKey;
  final List<String> enabledModelIds;

  bool sameIdentity(_CodexSupplierBinding other) {
    return supplierId == other.supplierId &&
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
