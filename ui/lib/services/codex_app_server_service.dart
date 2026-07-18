import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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

enum CodexApprovalRequestKind {
  commandExecution,
  fileChange,
  permissions,
}

abstract class CodexApprovalResponsePayload {
  const CodexApprovalResponsePayload();

  Map<String, dynamic> toJson();
}

class CodexCommandExecutionApprovalResponsePayload
    extends CodexApprovalResponsePayload {
  const CodexCommandExecutionApprovalResponsePayload({
    required this.decision,
  });

  final String decision;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'decision': decision,
      };
}

class CodexFileChangeApprovalResponsePayload
    extends CodexApprovalResponsePayload {
  const CodexFileChangeApprovalResponsePayload({
    required this.decision,
  });

  final String decision;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'decision': decision,
      };
}

class CodexPermissionsApprovalResponsePayload
    extends CodexApprovalResponsePayload {
  const CodexPermissionsApprovalResponsePayload({
    required this.permissions,
    this.scope = 'turn',
  });

  final Map<String, dynamic> permissions;
  final String scope;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'permissions': permissions,
        'scope': scope,
      };
}

abstract class CodexApprovalRequestPayload {
  const CodexApprovalRequestPayload({
    required this.requestId,
    required this.sessionGeneration,
    required this.serverRequestMethod,
    required this.params,
  });

  final Object requestId;
  final int sessionGeneration;
  final String serverRequestMethod;
  final Map<String, dynamic> params;

  CodexApprovalRequestKind get kind;

  CodexApprovalResponsePayload responseFor({required bool accepted});

  factory CodexApprovalRequestPayload.fromCardData(
    Map<String, dynamic> cardData,
  ) {
    final requestId = cardData['requestId'];
    if (requestId is! String && requestId is! num) {
      throw const FormatException(
        'Approval requestId must be a string or number',
      );
    }
    final sessionGeneration = _intOrNull(cardData['sessionGeneration']);
    if (sessionGeneration == null || sessionGeneration < 0) {
      throw const FormatException(
        'Approval sessionGeneration is missing or invalid',
      );
    }
    final serverRequestMethod =
        _stringOrNull(cardData['serverRequestMethod']);
    if (serverRequestMethod == null) {
      throw const FormatException('Approval serverRequestMethod is missing');
    }
    final params = _approvalParamsFromCardData(cardData);
    return switch (serverRequestMethod) {
      'item/commandExecution/requestApproval' =>
        CodexCommandExecutionApprovalRequestPayload(
          requestId: requestId,
          sessionGeneration: sessionGeneration,
          serverRequestMethod: serverRequestMethod,
          params: params,
        ),
      'item/fileChange/requestApproval' =>
        CodexFileChangeApprovalRequestPayload(
          requestId: requestId,
          sessionGeneration: sessionGeneration,
          serverRequestMethod: serverRequestMethod,
          params: params,
        ),
      'item/permissions/requestApproval' =>
        CodexPermissionsApprovalRequestPayload(
          requestId: requestId,
          sessionGeneration: sessionGeneration,
          serverRequestMethod: serverRequestMethod,
          params: params,
        ),
      _ => throw FormatException(
          'Unsupported approval method: $serverRequestMethod',
        ),
    };
  }
}

class CodexCommandExecutionApprovalRequestPayload
    extends CodexApprovalRequestPayload {
  const CodexCommandExecutionApprovalRequestPayload({
    required super.requestId,
    required super.sessionGeneration,
    required super.serverRequestMethod,
    required super.params,
  });

  @override
  CodexApprovalRequestKind get kind =>
      CodexApprovalRequestKind.commandExecution;

  @override
  CodexApprovalResponsePayload responseFor({required bool accepted}) {
    return CodexCommandExecutionApprovalResponsePayload(
      decision: accepted ? 'accept' : 'decline',
    );
  }
}

class CodexFileChangeApprovalRequestPayload
    extends CodexApprovalRequestPayload {
  const CodexFileChangeApprovalRequestPayload({
    required super.requestId,
    required super.sessionGeneration,
    required super.serverRequestMethod,
    required super.params,
  });

  @override
  CodexApprovalRequestKind get kind => CodexApprovalRequestKind.fileChange;

  @override
  CodexApprovalResponsePayload responseFor({required bool accepted}) {
    return CodexFileChangeApprovalResponsePayload(
      decision: accepted ? 'accept' : 'decline',
    );
  }
}

class CodexPermissionsApprovalRequestPayload
    extends CodexApprovalRequestPayload {
  CodexPermissionsApprovalRequestPayload({
    required Object requestId,
    required int sessionGeneration,
    required String serverRequestMethod,
    required Map<String, dynamic> params,
  }) : requestedPermissions = _permissionsFromParams(params),
       super(
         requestId: requestId,
         sessionGeneration: sessionGeneration,
         serverRequestMethod: serverRequestMethod,
         params: params,
       );

  final Map<String, dynamic> requestedPermissions;

  @override
  CodexApprovalRequestKind get kind => CodexApprovalRequestKind.permissions;

  @override
  CodexApprovalResponsePayload responseFor({required bool accepted}) {
    return CodexPermissionsApprovalResponsePayload(
      permissions: accepted
          ? Map<String, dynamic>.from(requestedPermissions)
          : <String, dynamic>{},
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
      StreamController<Map<String, dynamic>>.broadcast(
        onListen: _ensureEventSubscription,
        onCancel: _cancelEventSubscriptionWhenIdle,
      );
  static StreamSubscription<dynamic>? _nativeEventSubscription;
  static Timer? _eventRetryTimer;
  static bool _eventSubscriptionStarting = false;
  static int _eventRetryAttempt = 0;

  static Stream<Map<String, dynamic>> get events {
    return _eventController.stream;
  }

  static int get eventRetryAttemptForTesting => _eventRetryAttempt;

  static bool get hasEventSubscriptionForTesting =>
      _nativeEventSubscription != null || _eventSubscriptionStarting;

  static Duration eventRetryDelayForAttempt(int attempt) {
    final normalizedAttempt = attempt < 1 ? 1 : attempt;
    final exponent = (normalizedAttempt - 1).clamp(0, 5).toInt();
    return Duration(milliseconds: 250 * (1 << exponent));
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
    /// B38 T6: permission triad — must match current UI mode so new threads
    /// do not silently inherit Kotlin defaults (on-request / workspace only).
    String? approvalPolicy,
    String? approvalsReviewer,
    /// SandboxPolicy object; Kotlin [resolveCodexSandboxMode] maps `type` to
    /// ThreadStartParams `sandbox` kebab string. Prefer this over bare
    /// [sandbox] when writableRoots matter for turn/settings consistency.
    Map<String, dynamic>? sandboxPolicy,
    /// Optional explicit SandboxMode kebab/camel string. Wins over policy
    /// object type when both are set (Kotlin prefers explicit `sandbox`).
    String? sandbox,
  }) {
    final args = <String, dynamic>{
      if (conversationId != null) 'conversationId': conversationId,
      if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
      if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
      if (effort != null && effort.trim().isNotEmpty) 'effort': effort.trim(),
      if (collaborationMode != null && collaborationMode.trim().isNotEmpty)
        'collaborationMode': collaborationMode.trim(),
      if (approvalPolicy != null && approvalPolicy.trim().isNotEmpty)
        'approvalPolicy': approvalPolicy.trim(),
      if (approvalsReviewer != null && approvalsReviewer.trim().isNotEmpty)
        'approvalsReviewer': approvalsReviewer.trim(),
      if (sandboxPolicy != null) 'sandboxPolicy': sandboxPolicy,
      if (sandbox != null && sandbox.trim().isNotEmpty) 'sandbox': sandbox.trim(),
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

  /// Provider true source for Codex model menu ids (B38 T3).
  ///
  /// `GET {localConfig.baseUrl}/models` with Bearer [apiKey] from the same
  /// `config/local/read` source used for conf/auth. [baseUrl] may already
  /// include `/v1` — path is `{baseUrl}/models`, never forced `/api/v1/models`.
  ///
  /// Returns OpenAI-compatible ids from `data[].id` (order preserved).
  /// Does **not** use sandbox `~/.codex` catalog or app-server `model/list`.
  /// Never logs the API key.
  static Future<CodexHttpModelsResult> listModelsFromProviderHttp({
    String? baseUrl,
    String? apiKey,
    Duration timeout = const Duration(seconds: 15),
    http.Client? client,
  }) async {
    final String resolvedBase;
    final String resolvedKey;
    if (baseUrl != null && apiKey != null) {
      resolvedBase = baseUrl.trim();
      resolvedKey = apiKey.trim();
    } else {
      final local = await readLocalConfig();
      resolvedBase = (baseUrl ?? local.baseUrl).trim();
      resolvedKey = (apiKey ?? local.apiKey).trim();
    }

    final normalizedBase = _normalizeProviderBaseUrl(resolvedBase);
    if (normalizedBase.isEmpty) {
      throw StateError('Codex localConfig.baseUrl is empty; cannot list models');
    }
    if (resolvedKey.isEmpty) {
      throw StateError('Codex localConfig.apiKey is empty; cannot list models');
    }

    final uri = Uri.parse('$normalizedBase/models');
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final response = await httpClient
          .get(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $resolvedKey',
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CodexHttpModelsException(
          'HTTP ${response.statusCode} listing models from provider',
          statusCode: response.statusCode,
          endpoint: uri.toString(),
        );
      }
      final ids = _parseOpenAiModelsDataIds(response.body);
      return CodexHttpModelsResult(
        modelIds: ids,
        endpoint: uri.toString(),
        statusCode: response.statusCode,
        source: 'http_v1',
      );
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
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
    required CodexApprovalRequestPayload request,
    required bool accepted,
  }) {
    return _respondToServerRequest(
      requestId: request.requestId,
      sessionGeneration: request.sessionGeneration,
      serverRequestMethod: request.serverRequestMethod,
      response: request.responseFor(accepted: accepted).toJson(),
    );
  }

  static Future<Map<String, dynamic>> respondToUserInput({
    required Object requestId,
    required int sessionGeneration,
    required String serverRequestMethod,
    required String questionId,
    required List<String> answers,
  }) {
    return _respondToServerRequest(
      requestId: requestId,
      sessionGeneration: sessionGeneration,
      serverRequestMethod: serverRequestMethod,
      response: <String, dynamic>{
        'answers': {
          questionId: {'answers': answers},
        },
      },
    );
  }

  static Future<Map<String, dynamic>> ignoreUserInput({
    required Object requestId,
    required int sessionGeneration,
    required String serverRequestMethod,
  }) {
    return _respondToServerRequest(
      requestId: requestId,
      sessionGeneration: sessionGeneration,
      serverRequestMethod: serverRequestMethod,
      response: <String, dynamic>{'answers': <String, dynamic>{}},
    );
  }

  static Future<Map<String, dynamic>> _respondToServerRequest({
    required Object requestId,
    required int sessionGeneration,
    required String serverRequestMethod,
    required Map<String, dynamic> response,
  }) {
    final normalizedMethod = serverRequestMethod.trim();
    if (requestId is! String && requestId is! num) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'must be a string or number',
      );
    }
    if (sessionGeneration < 0) {
      throw ArgumentError.value(
        sessionGeneration,
        'sessionGeneration',
        'must be non-negative',
      );
    }
    if (normalizedMethod.isEmpty) {
      throw ArgumentError.value(
        serverRequestMethod,
        'serverRequestMethod',
        'must not be empty',
      );
    }
    return _invokeMap('respondToServerRequest', {
      'requestId': requestId,
      'sessionGeneration': sessionGeneration,
      'serverRequestMethod': normalizedMethod,
      'response': response,
    });
  }

  static void _ensureEventSubscription() {
    if (_nativeEventSubscription != null ||
        _eventSubscriptionStarting ||
        !_eventController.hasListener) {
      return;
    }
    _eventRetryTimer?.cancel();
    _eventRetryTimer = null;
    _eventSubscriptionStarting = true;
    try {
      final subscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          _eventRetryAttempt = 0;
          final normalized = _normalizeMap(event);
          if (normalized != null) {
            _eventController.add(normalized);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleNativeEventSubscriptionEnded(error: error);
        },
        onDone: () => _handleNativeEventSubscriptionEnded(),
        cancelOnError: true,
      );
      _nativeEventSubscription = subscription;
      _eventSubscriptionStarting = false;
    } catch (error) {
      _eventSubscriptionStarting = false;
      _handleNativeEventSubscriptionEnded(error: error);
    }
  }

  static void _handleNativeEventSubscriptionEnded({Object? error}) {
    final subscription = _nativeEventSubscription;
    _nativeEventSubscription = null;
    _eventSubscriptionStarting = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (error != null && _eventController.hasListener) {
      _eventController.add({
        'method': 'codex/flutterEventError',
        'message': {
          'method': 'codex/flutterEventError',
          'params': {'error': error.toString()},
        },
      });
    }
    _scheduleEventSubscriptionRetry();
  }

  static void _scheduleEventSubscriptionRetry() {
    if (!_eventController.hasListener || _eventRetryTimer != null) {
      return;
    }
    _eventRetryAttempt =
        _eventRetryAttempt >= 32 ? 32 : _eventRetryAttempt + 1;
    final delay = eventRetryDelayForAttempt(_eventRetryAttempt);
    _eventRetryTimer = Timer(delay, () {
      _eventRetryTimer = null;
      _ensureEventSubscription();
    });
  }

  static void _cancelEventSubscriptionWhenIdle() {
    if (_eventController.hasListener) {
      return;
    }
    _eventRetryTimer?.cancel();
    _eventRetryTimer = null;
    _eventRetryAttempt = 0;
    final subscription = _nativeEventSubscription;
    _nativeEventSubscription = null;
    _eventSubscriptionStarting = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  static Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    // B38 T5: MissingPlugin on connect/status is often a brief engine/channel
    // rebind window (half-screen clear, activity reattach). Retry short-lived.
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final result =
            await _methodChannel.invokeMethod<dynamic>(method, args);
        return _normalizeMap(result) ?? <String, dynamic>{};
      } on MissingPluginException catch (error) {
        lastError = error;
        if (attempt >= maxAttempts) {
          rethrow;
        }
        // 50/100ms: enough for MainActivity reconfigure without stalling UI.
        await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
      }
    }
    // Unreachable; keep analyzer happy.
    throw lastError ??
        MissingPluginException('No implementation found for method $method');
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

Map<String, dynamic> _approvalParamsFromCardData(
  Map<String, dynamic> cardData,
) {
  final direct = _normalizeMap(cardData['requestParams']);
  if (direct != null) {
    return direct;
  }
  final raw = cardData['rawParamsJson']?.toString().trim() ?? '';
  if (raw.isEmpty) {
    return <String, dynamic>{};
  }
  final decoded = jsonDecode(raw);
  final params = _normalizeMap(decoded);
  if (params == null) {
    throw const FormatException('Approval params must be a JSON object');
  }
  return params;
}

Map<String, dynamic> _permissionsFromParams(Map<String, dynamic> params) {
  final permissions = _normalizeMap(params['permissions']);
  if (permissions == null) {
    throw const FormatException(
      'Permissions approval request is missing permissions',
    );
  }
  return Map<String, dynamic>.unmodifiable(permissions);
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

/// Result of [CodexAppServerService.listModelsFromProviderHttp].
class CodexHttpModelsResult {
  const CodexHttpModelsResult({
    required this.modelIds,
    required this.endpoint,
    required this.statusCode,
    this.source = 'http_v1',
  });

  /// Provider `data[].id` values, order preserved, no invent display names.
  final List<String> modelIds;
  final String endpoint;
  final int statusCode;
  final String source;
}

class CodexHttpModelsException implements Exception {
  CodexHttpModelsException(
    this.message, {
    this.statusCode,
    this.endpoint,
  });

  final String message;
  final int? statusCode;
  final String? endpoint;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' status=$statusCode';
    final ep = (endpoint == null || endpoint!.isEmpty) ? '' : ' endpoint=$endpoint';
    return 'CodexHttpModelsException: $message$code$ep';
  }
}

/// Strip trailing slashes only; keep `/v1` if present (do not rewrite path).
String _normalizeProviderBaseUrl(String baseUrl) {
  var value = baseUrl.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// Parse OpenAI-compatible `{ "data": [ { "id": "..." }, ... ] }` body.
List<String> _parseOpenAiModelsDataIds(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    throw const FormatException('Provider /models body is not a JSON object');
  }
  final data = decoded['data'];
  if (data is! List) {
    throw const FormatException('Provider /models missing data[] array');
  }
  final seen = <String>{};
  final ids = <String>[];
  for (final item in data) {
    if (item is! Map) continue;
    final id = item['id']?.toString().trim() ?? '';
    if (id.isEmpty || !seen.add(id)) continue;
    ids.add(id);
  }
  return ids;
}
