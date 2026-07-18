import 'package:ui/services/codex_app_server_service.dart';

typedef CodexLocalConfigReader = Future<CodexLocalConfig> Function();
typedef CodexProviderHttpModelReader =
    Future<CodexHttpModelsResult> Function({
      required String baseUrl,
      required String apiKey,
    });
typedef CodexAppServerModelReader =
    Future<Map<String, dynamic>> Function();
typedef CodexRunConfigReader = Future<Map<String, dynamic>> Function();

/// Fetches the Codex model catalog from the source owned by the active runtime.
///
/// Local runtimes use provider HTTP as the model-id truth and app-server only
/// for optional effort metadata. Remote runtimes never inspect the phone's
/// local provider base URL or API key; their app-server catalog is authoritative.
class CodexModelCatalogLoader {
  CodexModelCatalogLoader({
    CodexLocalConfigReader? readLocalConfig,
    CodexProviderHttpModelReader? readProviderHttpModels,
    CodexAppServerModelReader? readAppServerModels,
    CodexRunConfigReader? readRunConfig,
  }) : _readLocalConfig =
           readLocalConfig ?? CodexAppServerService.readLocalConfig,
       _readProviderHttpModels =
           readProviderHttpModels ?? _defaultReadProviderHttpModels,
       _readAppServerModels =
           readAppServerModels ?? CodexAppServerService.listModels,
       _readRunConfig = readRunConfig ?? CodexAppServerService.readConfig;

  final CodexLocalConfigReader _readLocalConfig;
  final CodexProviderHttpModelReader _readProviderHttpModels;
  final CodexAppServerModelReader _readAppServerModels;
  final CodexRunConfigReader _readRunConfig;

  static Future<CodexHttpModelsResult> _defaultReadProviderHttpModels({
    required String baseUrl,
    required String apiKey,
  }) {
    return CodexAppServerService.listModelsFromProviderHttp(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
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

    CodexLocalConfig? localConfig;
    CodexHttpModelsResult? httpResult;
    Object? httpError;
    try {
      localConfig = await _readLocalConfig();
      httpResult = await _readProviderHttpModels(
        baseUrl: localConfig.baseUrl,
        apiKey: localConfig.apiKey,
      );
    } catch (error) {
      httpError = error;
    }

    if (httpResult == null) {
      final appServerResponse = await _readAppServerModels();
      return CodexModelCatalogSourceResult(
        source: 'app_server_fallback',
        appServerResponse: appServerResponse,
        useAppServerModelIds: true,
        httpError: httpError,
        providerIdentity: _localProviderIdentity(localConfig),
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
    return CodexModelCatalogSourceResult(
      source: httpResult.source,
      httpResult: httpResult,
      appServerResponse: appServerResponse,
      useAppServerModelIds: false,
      metadataError: metadataError,
      providerIdentity: _localProviderIdentity(localConfig),
      runConfigResponse: runConfigResponse,
      runConfigError: runConfigError,
    );
  }
}

class CodexModelCatalogSourceResult {
  const CodexModelCatalogSourceResult({
    required this.source,
    required this.appServerResponse,
    required this.useAppServerModelIds,
    required this.providerIdentity,
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

String _localProviderIdentity(CodexLocalConfig? config) {
  if (config == null) {
    return 'local:unavailable';
  }
  final baseUrl = config.baseUrl.trim();
  final fingerprint = Object.hash(baseUrl, config.apiKey.trim());
  return 'local:$baseUrl#$fingerprint';
}
