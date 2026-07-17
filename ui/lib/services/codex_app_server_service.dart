import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

class CodexStatus {
  const CodexStatus({
    required this.connected,
    required this.ready,
    this.version,
    this.error,
    this.codexHome,
    this.cwd,
    this.runtime,
    this.remoteEnabled = false,
    this.remoteBridgeUrl,
    this.remoteCwd,
    this.remoteConfigured = false,
    this.remoteTransport,
    this.remoteDesktopAvailable,
    this.remoteActiveConnections,
    this.remoteUptimeMs,
  });

  final bool connected;
  final bool ready;
  final String? version;
  final String? error;
  final String? codexHome;
  final String? cwd;
  final String? runtime;
  final bool remoteEnabled;
  final String? remoteBridgeUrl;
  final String? remoteCwd;
  final bool remoteConfigured;
  final String? remoteTransport;
  final bool? remoteDesktopAvailable;
  final int? remoteActiveConnections;
  final int? remoteUptimeMs;

  bool get canConnect => ready;

  factory CodexStatus.fromMap(Map<dynamic, dynamic>? map) {
    final source = map ?? const <dynamic, dynamic>{};
    return CodexStatus(
      connected: source['connected'] == true,
      ready: source['ready'] == true,
      version: _stringOrNull(source['version']),
      error: _stringOrNull(source['error']),
      codexHome: _stringOrNull(source['codexHome']),
      cwd: _stringOrNull(source['cwd']),
      runtime: _stringOrNull(source['runtime']),
      remoteEnabled: source['remoteEnabled'] == true,
      remoteBridgeUrl: _stringOrNull(source['remoteBridgeUrl']),
      remoteCwd: _stringOrNull(source['remoteCwd']),
      remoteConfigured: source['remoteConfigured'] == true,
      remoteTransport: _stringOrNull(source['remoteTransport']),
      remoteDesktopAvailable: _boolOrNull(source['remoteDesktopAvailable']),
      remoteActiveConnections: _intOrNull(source['remoteActiveConnections']),
      remoteUptimeMs: _intOrNull(source['remoteUptimeMs']),
    );
  }

  static const disconnected = CodexStatus(connected: false, ready: false);
}

class CodexLocalConfig {
  const CodexLocalConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.codexHome,
    this.serviceTier = '',
    /// Mirror of config.toml `[features].fast_mode`. Null means unknown /
    /// not provided and does **not** enable Fast by itself (default off).
    this.fastMode,
    /// Mirror of config.toml `[features].auto_compaction`. Null means unknown
    /// / not provided (UI defaults on for B27 discoverability).
    this.autoCompaction,
    /// Mirror of top-level `omnimind_context_token_threshold`. Null means missing
    /// (UI may default to 128000).
    this.contextTokenThreshold,
    this.modelReasoningEffort = '',
    this.defaultGoal = '',
    this.remoteEnabled = false,
    this.remoteBridgeUrl = '',
    this.remoteBridgeToken = '',
    this.remoteCwd = '',
    this.remoteConfigured = false,
    this.runtime,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final String? codexHome;
  final String serviceTier;

  /// Explicit `[features].fast_mode` from config. Null/false do not enable Fast.
  final bool? fastMode;

  /// Explicit `[features].auto_compaction` from config. Null means unknown.
  final bool? autoCompaction;

  /// Top-level `omnimind_context_token_threshold`. Null when absent from conf.
  final int? contextTokenThreshold;
  final String modelReasoningEffort;
  final String defaultGoal;
  final bool remoteEnabled;
  final String remoteBridgeUrl;
  final String remoteBridgeToken;
  final String remoteCwd;
  final bool remoteConfigured;
  final String? runtime;

  /// Fast is on when service tier is fast/priority **or** [fastMode] is true.
  /// Missing / null [fastMode] defaults off (never treat absence as on).
  bool get isFastEnabled {
    final tier = serviceTier.trim().toLowerCase();
    if (tier == 'fast' || tier == 'priority') {
      return true;
    }
    return fastMode == true;
  }

  /// Auto compaction UI default: on when key is missing (Codex-ish default).
  bool get isAutoCompactionEnabled => autoCompaction ?? true;

  factory CodexLocalConfig.fromMap(Map<dynamic, dynamic>? map) {
    final source = map ?? const <dynamic, dynamic>{};
    return CodexLocalConfig(
      baseUrl: _stringOrNull(source['baseUrl']) ?? '',
      model: _stringOrNull(source['model']) ?? '',
      apiKey: _stringOrNull(source['apiKey']) ?? '',
      codexHome: _stringOrNull(source['codexHome']),
      serviceTier: _stringOrNull(source['serviceTier']) ?? '',
      fastMode: _boolOrNull(source['fastMode']) ??
          _boolOrNull(source['fast_mode']),
      autoCompaction: _boolOrNull(source['autoCompaction']) ??
          _boolOrNull(source['auto_compaction']),
      contextTokenThreshold: _intOrNull(source['contextTokenThreshold']) ??
          _intOrNull(source['omnimind_context_token_threshold']) ??
          _intOrNull(source['context_token_threshold']),
      modelReasoningEffort:
          _stringOrNull(source['modelReasoningEffort']) ?? '',
      defaultGoal: _stringOrNull(source['defaultGoal']) ?? '',
      remoteEnabled: source['remoteEnabled'] == true,
      remoteBridgeUrl: _stringOrNull(source['remoteBridgeUrl']) ?? '',
      remoteBridgeToken: _stringOrNull(source['remoteBridgeToken']) ?? '',
      remoteCwd: _stringOrNull(source['remoteCwd']) ?? '',
      remoteConfigured: source['remoteConfigured'] == true,
      runtime: _stringOrNull(source['runtime']),
    );
  }
}

class CodexRemoteDirectoryEntry {
  const CodexRemoteDirectoryEntry({
    required this.name,
    required this.path,
    required this.type,
    this.hidden = false,
  });

  final String name;
  final String path;
  final String type;
  final bool hidden;

  bool get isDirectory => type == 'directory';

  factory CodexRemoteDirectoryEntry.fromMap(Map<dynamic, dynamic> map) {
    return CodexRemoteDirectoryEntry(
      name: _stringOrNull(map['name']) ?? '',
      path: _stringOrNull(map['path']) ?? '',
      type: _stringOrNull(map['type']) ?? 'other',
      hidden: map['hidden'] == true,
    );
  }
}

class CodexRemoteDirectoryList {
  const CodexRemoteDirectoryList({
    required this.ok,
    required this.path,
    this.parent,
    this.cwd,
    this.home,
    this.error,
    this.entries = const <CodexRemoteDirectoryEntry>[],
  });

  final bool ok;
  final String path;
  final String? parent;
  final String? cwd;
  final String? home;
  final String? error;
  final List<CodexRemoteDirectoryEntry> entries;

  factory CodexRemoteDirectoryList.fromMap(Map<dynamic, dynamic>? map) {
    final source = map ?? const <dynamic, dynamic>{};
    final rawEntries = source['entries'];
    return CodexRemoteDirectoryList(
      ok: source['ok'] == true,
      path: _stringOrNull(source['path']) ?? '',
      parent: _stringOrNull(source['parent']),
      cwd: _stringOrNull(source['cwd']),
      home: _stringOrNull(source['home']),
      error: _stringOrNull(source['error']),
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map(CodexRemoteDirectoryEntry.fromMap)
                .where(
                  (entry) => entry.name.isNotEmpty && entry.path.isNotEmpty,
                )
                .toList(growable: false)
          : const <CodexRemoteDirectoryEntry>[],
    );
  }
}

class CodexRemoteFilePayload {
  const CodexRemoteFilePayload({
    required this.ok,
    required this.path,
    required this.name,
    this.type = 'file',
    this.size,
    this.mtimeMs,
    this.mimeType = 'application/octet-stream',
    this.previewKind = 'file',
    this.encoding,
    this.content,
    this.dataBase64,
    this.truncated = false,
    this.error,
  });

  final bool ok;
  final String path;
  final String name;
  final String type;
  final int? size;
  final double? mtimeMs;
  final String mimeType;
  final String previewKind;
  final String? encoding;
  final String? content;
  final String? dataBase64;
  final bool truncated;
  final String? error;

  bool get isTextLike => previewKind == 'text' || previewKind == 'code';

  Uint8List? get bytes {
    final encoded = dataBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  factory CodexRemoteFilePayload.fromMap(Map<dynamic, dynamic>? map) {
    final source = map ?? const <dynamic, dynamic>{};
    return CodexRemoteFilePayload(
      ok: source['ok'] == true,
      path: _stringOrNull(source['path']) ?? '',
      name: _stringOrNull(source['name']) ?? '',
      type: _stringOrNull(source['type']) ?? 'file',
      size: _intOrNull(source['size']),
      mtimeMs: _doubleOrNull(source['mtimeMs']),
      mimeType: _stringOrNull(source['mimeType']) ?? 'application/octet-stream',
      previewKind: _stringOrNull(source['previewKind']) ?? 'file',
      encoding: _stringOrNull(source['encoding']),
      content: source['content']?.toString(),
      dataBase64: _stringOrNull(source['dataBase64']),
      truncated: source['truncated'] == true,
      error: _stringOrNull(source['error']),
    );
  }
}

class CodexAppServerService {
  CodexAppServerService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'cn.com.omnimind.bot/CodexAppServer',
  );
  static const EventChannel _eventChannel = EventChannel(
    'cn.com.omnimind.bot/CodexAppServerEvents',
  );

  static final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  static StreamSubscription<dynamic>? _nativeEventSubscription;

  static Stream<Map<String, dynamic>> get events {
    _ensureEventSubscription();
    return _eventController.stream;
  }

  static Future<CodexStatus> status() async {
    final result = await _invokeMap('status');
    return CodexStatus.fromMap(result);
  }

  static Future<CodexStatus> connect() async {
    final result = await _invokeMap('connect');
    return CodexStatus.fromMap(result);
  }

  static Future<CodexStatus> disconnect() async {
    final result = await _invokeMap('disconnect');
    return CodexStatus.fromMap(result);
  }

  static Future<Map<String, dynamic>> startThread({
    int? conversationId,
    String? cwd,
    String? model,
    String? effort,
    String? collaborationMode,
    String? serviceTier,
    /// When true, sends `serviceTier: null` (JSON null clear). Prefer
    /// [updateThreadSettings] for live threads; native start path may still
    /// drop null until Kotlin optional-param helper preserves it.
    bool clearServiceTier = false,
  }) {
    final args = <String, dynamic>{
      if (conversationId != null) 'conversationId': conversationId,
      if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (effort != null && effort.trim().isNotEmpty) 'effort': effort.trim(),
      if (collaborationMode != null && collaborationMode.trim().isNotEmpty)
        'collaborationMode': collaborationMode.trim(),
    };
    _putServiceTierArg(
      args,
      serviceTier: serviceTier,
      clearServiceTier: clearServiceTier,
    );
    return _invokeMap('thread/start', args);
  }

  static Future<Map<String, dynamic>> resumeThread({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/resume', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  static Future<Map<String, dynamic>> readThread({
    String? threadId,
    int? conversationId,
    bool includeTurns = true,
  }) {
    return _invokeMap('thread/read', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      'includeTurns': includeTurns,
    });
  }

  static Future<Map<String, dynamic>> listThreads({
    int limit = 50,
    String? cursor,
  }) {
    return _invokeMap('thread/list', {
      'limit': limit,
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    });
  }

  static Future<Map<String, dynamic>> listLoadedThreads() {
    return _invokeMap('thread/loaded/list');
  }

  static Future<Map<String, dynamic>> archiveThread({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/archive', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  static Future<Map<String, dynamic>> unarchiveThread({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/unarchive', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  static Future<Map<String, dynamic>> setThreadName({
    String? threadId,
    int? conversationId,
    required String name,
  }) {
    return _invokeMap('thread/name/set', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      'name': name,
    });
  }

  static Future<Map<String, dynamic>> startTurn({
    String? threadId,
    int? conversationId,
    required String text,
    String? cwd,
    String? approvalPolicy,
    String? approvalsReviewer,
    Map<String, dynamic>? sandboxPolicy,
    String? model,
    String? effort,
    String? collaborationMode,
    String? serviceTier,
    /// Explicit JSON-null clear for this turn (schema allows null). Prefer
    /// clearing via [updateThreadSettings] on the live thread when possible.
    bool clearServiceTier = false,
  }) {
    final args = <String, dynamic>{
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
      if (approvalPolicy != null && approvalPolicy.trim().isNotEmpty)
        'approvalPolicy': approvalPolicy.trim(),
      if (approvalsReviewer != null && approvalsReviewer.trim().isNotEmpty)
        'approvalsReviewer': approvalsReviewer.trim(),
      if (sandboxPolicy != null) 'sandboxPolicy': sandboxPolicy,
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (effort != null && effort.trim().isNotEmpty) 'effort': effort.trim(),
      if (collaborationMode != null && collaborationMode.trim().isNotEmpty)
        'collaborationMode': collaborationMode.trim(),
      'text': text,
    };
    _putServiceTierArg(
      args,
      serviceTier: serviceTier,
      clearServiceTier: clearServiceTier,
    );
    return _invokeMap('turn/start', args);
  }

  static Future<Map<String, dynamic>> startReview({
    String? threadId,
    int? conversationId,
    String? cwd,
    Map<String, dynamic>? target,
    String? approvalPolicy,
    String? approvalsReviewer,
    Map<String, dynamic>? sandboxPolicy,
    String? model,
    String? effort,
    String? collaborationMode,
    String? serviceTier,
    bool clearServiceTier = false,
  }) {
    final args = <String, dynamic>{
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
      'target': target ?? <String, dynamic>{'type': 'uncommittedChanges'},
      if (approvalPolicy != null && approvalPolicy.trim().isNotEmpty)
        'approvalPolicy': approvalPolicy.trim(),
      if (approvalsReviewer != null && approvalsReviewer.trim().isNotEmpty)
        'approvalsReviewer': approvalsReviewer.trim(),
      if (sandboxPolicy != null) 'sandboxPolicy': sandboxPolicy,
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (effort != null && effort.trim().isNotEmpty) 'effort': effort.trim(),
      if (collaborationMode != null && collaborationMode.trim().isNotEmpty)
        'collaborationMode': collaborationMode.trim(),
    };
    _putServiceTierArg(
      args,
      serviceTier: serviceTier,
      clearServiceTier: clearServiceTier,
    );
    return _invokeMap('review/start', args);
  }

  static Future<Map<String, dynamic>> startCompact({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/compact/start', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  static Future<Map<String, dynamic>> getThreadGoal({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/goal/get', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  static Future<Map<String, dynamic>> setThreadGoal({
    String? threadId,
    int? conversationId,
    required String objective,
    String status = 'active',
  }) {
    return _invokeMap('thread/goal/set', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      'objective': objective.trim(),
      if (status.trim().isNotEmpty) 'status': status.trim(),
    });
  }

  static Future<Map<String, dynamic>> clearThreadGoal({
    String? threadId,
    int? conversationId,
  }) {
    return _invokeMap('thread/goal/clear', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  /// Update live thread run settings (model/effort/etc.) via app-server
  /// `thread/settings/update`.
  ///
  /// Schema: for `serviceTier`, **null clears** the current tier; **omission**
  /// leaves it unchanged. Callers that need to turn Fast off must pass
  /// [clearServiceTier]: true (sends JSON null). A non-empty [serviceTier]
  /// string sets the tier; empty string alone is still treated as omit.
  static Future<Map<String, dynamic>> updateThreadSettings({
    required String threadId,
    String? model,
    String? effort,
    String? serviceTier,
    bool clearServiceTier = false,
    String? collaborationMode,
    String? summary,
    String? approvalPolicy,
    String? approvalsReviewer,
    Map<String, dynamic>? sandboxPolicy,
    String? permissions,
    String? cwd,
    String? personality,
  }) {
    final resolvedThreadId = threadId.trim();
    if (resolvedThreadId.isEmpty) {
      throw ArgumentError.value(threadId, 'threadId', 'must not be empty');
    }
    final args = <String, dynamic>{
      'threadId': resolvedThreadId,
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (effort != null && effort.trim().isNotEmpty) 'effort': effort.trim(),
      if (collaborationMode != null && collaborationMode.trim().isNotEmpty)
        'collaborationMode': collaborationMode.trim(),
      if (summary != null && summary.trim().isNotEmpty)
        'summary': summary.trim(),
      if (approvalPolicy != null && approvalPolicy.trim().isNotEmpty)
        'approvalPolicy': approvalPolicy.trim(),
      if (approvalsReviewer != null && approvalsReviewer.trim().isNotEmpty)
        'approvalsReviewer': approvalsReviewer.trim(),
      if (sandboxPolicy != null) 'sandboxPolicy': sandboxPolicy,
      if (permissions != null && permissions.trim().isNotEmpty)
        'permissions': permissions.trim(),
      if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
      if (personality != null && personality.trim().isNotEmpty)
        'personality': personality.trim(),
    };
    _putServiceTierArg(
      args,
      serviceTier: serviceTier,
      clearServiceTier: clearServiceTier,
    );
    return _invokeMap('thread/settings/update', args);
  }

  static Future<Map<String, dynamic>> listModels() {
    return _invokeMap('model/list', {'limit': 100});
  }

  static Future<Map<String, dynamic>> listCollaborationModes() {
    return _invokeMap('collaborationMode/list');
  }

  static Future<Map<String, dynamic>> readConfig() {
    return _invokeMap('config/read');
  }

  static Future<CodexLocalConfig> readLocalConfig() async {
    final result = await _invokeMap('config/local/read');
    return CodexLocalConfig.fromMap(result);
  }

  /// Persist OmniMind local Codex config.
  ///
  /// [fastMode] / [serviceTier] are optional so callers that only change
  /// remote cwd do not wipe billing prefs. When provided, both should be set
  /// together for Fast:
  /// - on: `fastMode: true`, `serviceTier: 'fast'`
  /// - off: `fastMode: false`, `serviceTier: ''` (explicit off; never omit
  ///   fastMode to mean off)
  ///
  /// [autoCompaction] is optional. When provided, writes
  /// `features.auto_compaction = true|false` without wiping other features.
  /// When omitted, native preserves the existing key.
  ///
  /// [contextTokenThreshold] is optional. When provided, writes top-level
  /// `omnimind_context_token_threshold = <n>`. When omitted (null), native
  /// preserves the existing key.
  static Future<CodexLocalConfig> writeLocalConfig({
    required String baseUrl,
    required String model,
    required String apiKey,
    String? serviceTier,
    bool? fastMode,
    bool? autoCompaction,
    int? contextTokenThreshold,
    String modelReasoningEffort = '',
    String defaultGoal = '',
    bool remoteEnabled = false,
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
  }) async {
    final result = await _invokeMap('config/local/write', {
      'baseUrl': baseUrl.trim(),
      'model': model.trim(),
      'apiKey': apiKey.trim(),
      if (serviceTier != null) 'serviceTier': serviceTier.trim(),
      if (fastMode != null) 'fastMode': fastMode,
      if (autoCompaction != null) 'autoCompaction': autoCompaction,
      if (contextTokenThreshold != null)
        'contextTokenThreshold': contextTokenThreshold,
      'modelReasoningEffort': modelReasoningEffort.trim(),
      'defaultGoal': defaultGoal.trim(),
      'remoteEnabled': remoteEnabled,
      'remoteBridgeUrl': remoteBridgeUrl.trim(),
      'remoteBridgeToken': remoteBridgeToken.trim(),
      'remoteCwd': remoteCwd.trim(),
    });
    return CodexLocalConfig.fromMap(result);
  }

  static Future<Map<String, dynamic>> testRemoteConfig({
    required String remoteBridgeUrl,
    required String remoteBridgeToken,
    required String remoteCwd,
  }) {
    return _invokeMap('config/remote/test', {
      'remoteBridgeUrl': remoteBridgeUrl.trim(),
      'remoteBridgeToken': remoteBridgeToken.trim(),
      'remoteCwd': remoteCwd.trim(),
    });
  }

  static Future<CodexRemoteDirectoryList> listRemoteDirectories({
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
    String? path,
  }) async {
    final result = await _invokeMap('config/remote/fs/list', {
      if (remoteBridgeUrl.trim().isNotEmpty)
        'remoteBridgeUrl': remoteBridgeUrl.trim(),
      if (remoteBridgeToken.trim().isNotEmpty)
        'remoteBridgeToken': remoteBridgeToken.trim(),
      if (remoteCwd.trim().isNotEmpty) 'remoteCwd': remoteCwd.trim(),
      if (path != null && path.trim().isNotEmpty) 'path': path.trim(),
    });
    return CodexRemoteDirectoryList.fromMap(result);
  }

  static Future<CodexRemoteFilePayload> readRemoteFile({
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
    required String path,
  }) async {
    final result = await _invokeMap('config/remote/fs/read', {
      if (remoteBridgeUrl.trim().isNotEmpty)
        'remoteBridgeUrl': remoteBridgeUrl.trim(),
      if (remoteBridgeToken.trim().isNotEmpty)
        'remoteBridgeToken': remoteBridgeToken.trim(),
      if (remoteCwd.trim().isNotEmpty) 'remoteCwd': remoteCwd.trim(),
      'path': path.trim(),
    });
    return CodexRemoteFilePayload.fromMap(result);
  }

  static Future<Map<String, dynamic>> writeRemoteFile({
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
    required String path,
    required String content,
  }) {
    return _invokeMap('config/remote/fs/write', {
      if (remoteBridgeUrl.trim().isNotEmpty)
        'remoteBridgeUrl': remoteBridgeUrl.trim(),
      if (remoteBridgeToken.trim().isNotEmpty)
        'remoteBridgeToken': remoteBridgeToken.trim(),
      if (remoteCwd.trim().isNotEmpty) 'remoteCwd': remoteCwd.trim(),
      'path': path.trim(),
      'content': content,
    });
  }

  static Future<Map<String, dynamic>> deleteRemotePath({
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
    required String path,
    bool recursive = false,
  }) {
    return _invokeMap('config/remote/fs/delete', {
      if (remoteBridgeUrl.trim().isNotEmpty)
        'remoteBridgeUrl': remoteBridgeUrl.trim(),
      if (remoteBridgeToken.trim().isNotEmpty)
        'remoteBridgeToken': remoteBridgeToken.trim(),
      if (remoteCwd.trim().isNotEmpty) 'remoteCwd': remoteCwd.trim(),
      'path': path.trim(),
      'recursive': recursive,
    });
  }

  static Future<Map<String, dynamic>> moveRemotePath({
    String remoteBridgeUrl = '',
    String remoteBridgeToken = '',
    String remoteCwd = '',
    required String path,
    required String destinationPath,
  }) {
    return _invokeMap('config/remote/fs/move', {
      if (remoteBridgeUrl.trim().isNotEmpty)
        'remoteBridgeUrl': remoteBridgeUrl.trim(),
      if (remoteBridgeToken.trim().isNotEmpty)
        'remoteBridgeToken': remoteBridgeToken.trim(),
      if (remoteCwd.trim().isNotEmpty) 'remoteCwd': remoteCwd.trim(),
      'path': path.trim(),
      'destinationPath': destinationPath.trim(),
    });
  }

  static Future<Map<String, dynamic>> steerTurn({
    String? threadId,
    int? conversationId,
    String? turnId,
    required String text,
  }) {
    return _invokeMap('turn/steer', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      if (turnId != null) 'turnId': turnId,
      'text': text,
    });
  }

  static Future<Map<String, dynamic>> interruptTurn({
    String? threadId,
    int? conversationId,
    String? turnId,
  }) {
    return _invokeMap('turn/interrupt', {
      if (threadId != null) 'threadId': threadId,
      if (conversationId != null) 'conversationId': conversationId,
      if (turnId != null) 'turnId': turnId,
    });
  }

  static Future<Map<String, dynamic>> readAccount() {
    return _invokeMap('account/read');
  }

  static Future<Map<String, dynamic>> startLogin({String type = 'chatgpt'}) {
    return _invokeMap('account/login/start', {'type': type});
  }

  static Future<Map<String, dynamic>> cancelLogin() {
    return _invokeMap('account/login/cancel');
  }

  static Future<Map<String, dynamic>> respondToApproval({
    required Object requestId,
    required bool accepted,
  }) {
    return _invokeMap('respondToServerRequest', {
      'requestId': requestId,
      'response': {'decision': accepted ? 'accept' : 'decline'},
    });
  }

  static Future<Map<String, dynamic>> respondToUserInput({
    required Object requestId,
    required String questionId,
    required List<String> answers,
  }) {
    return _invokeMap('respondToServerRequest', {
      'requestId': requestId,
      'response': {
        'answers': {
          questionId: {'answers': answers},
        },
      },
    });
  }

  static Future<Map<String, dynamic>> ignoreUserInput({
    required Object requestId,
  }) {
    return _invokeMap('respondToServerRequest', {
      'requestId': requestId,
      'response': {'answers': <String, dynamic>{}},
    });
  }

  static void _ensureEventSubscription() {
    if (_nativeEventSubscription != null) return;
    _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final normalized = _normalizeMap(event);
        if (normalized != null) {
          _eventController.add(normalized);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _eventController.add({
          'method': 'codex/flutterEventError',
          'message': {
            'method': 'codex/flutterEventError',
            'params': {'error': error.toString()},
          },
        });
      },
    );
  }

  static Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    final result = await _methodChannel.invokeMethod<dynamic>(method, args);
    return _normalizeMap(result) ?? <String, dynamic>{};
  }
}

/// Put `serviceTier` on [args] with three-way semantics:
/// - [clearServiceTier] true → JSON null clear (key present, value null)
/// - non-empty [serviceTier] → set string
/// - otherwise omit (leave unchanged / native default)
void _putServiceTierArg(
  Map<String, dynamic> args, {
  String? serviceTier,
  bool clearServiceTier = false,
}) {
  if (clearServiceTier) {
    args['serviceTier'] = null;
    return;
  }
  if (serviceTier != null && serviceTier.trim().isNotEmpty) {
    args['serviceTier'] = serviceTier.trim();
  }
}

Map<String, dynamic>? _normalizeMap(dynamic value) {
  if (value is! Map) return null;
  return value.map((key, nestedValue) {
    return MapEntry(key.toString(), _normalizeValue(nestedValue));
  });
}

dynamic _normalizeValue(dynamic value) {
  if (value is Map) {
    return value.map((key, nestedValue) {
      return MapEntry(key.toString(), _normalizeValue(nestedValue));
    });
  }
  if (value is List) {
    return value.map(_normalizeValue).toList();
  }
  return value;
}

String? _stringOrNull(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _intOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool? _boolOrNull(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value.toInt() != 0;
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  return switch (normalized) {
    'true' || '1' || 'yes' => true,
    'false' || '0' || 'no' => false,
    _ => null,
  };
}

double? _doubleOrNull(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
