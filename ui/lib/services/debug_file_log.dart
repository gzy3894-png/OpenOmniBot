import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// DEBUG-only external file logger for OmniBot Codex diagnostics (B10).
///
/// Preferred path:
/// `/storage/emulated/0/Download/OmniBotLogs/omnibot-debug-YYYYMMDD.log`
/// Fallback: app external files / application support under `OmniBotLogs/`.
///
/// Never logs full secrets (apiKey / token / password / etc.).
class DebugFileLog {
  DebugFileLog._();

  static const String _downloadRoot =
      '/storage/emulated/0/Download/OmniBotLogs';
  static const String _dirName = 'OmniBotLogs';
  static const int _maxLineChars = 4000;
  static const int _maxQueue = 400;

  static final List<String> _queue = <String>[];
  static bool _flushing = false;
  static Future<File?>? _fileFuture;
  static String? _resolvedPath;
  static bool _enabledOverride = true;

  /// Force-disable (tests). Default follows [kDebugMode].
  static set enabled(bool value) {
    _enabledOverride = value;
  }

  static bool get isEnabled => kDebugMode && _enabledOverride;

  /// Last successfully resolved log file path (may be null before first write).
  static String? get resolvedPath => _resolvedPath;

  static Future<void> log(
    String tag,
    String message, {
    Map<String, Object?>? fields,
  }) async {
    if (!isEnabled) return;
    final buffer = StringBuffer();
    buffer.write(_ts());
    buffer.write(' [');
    buffer.write(tag);
    buffer.write('] ');
    buffer.write(_redact(message));
    if (fields != null && fields.isNotEmpty) {
      for (final entry in fields.entries) {
        buffer.write(' ');
        buffer.write(entry.key);
        buffer.write('=');
        buffer.write(_formatField(entry.key, entry.value));
      }
    }
    _enqueue(buffer.toString());
    unawaited(_flush());
  }

  /// Composer submit: user-visible vs model-visible text.
  static Future<void> logComposer({
    required String display,
    required String actual,
    String? kind,
    String? threadId,
    int? conversationId,
  }) {
    return log(
      'composer',
      kind == null || kind.isEmpty ? 'submit' : 'submit:$kind',
      fields: <String, Object?>{
        'display': display,
        'actual': actual,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (conversationId != null) 'conversationId': conversationId,
      },
    );
  }

  /// Goal get / set / clear.
  static Future<void> logGoal(
    String action, {
    String? objective,
    String? threadId,
    int? conversationId,
    Object? error,
  }) {
    return log(
      'goal',
      action,
      fields: <String, Object?>{
        if (objective != null) 'objective': objective,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (conversationId != null) 'conversationId': conversationId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// Review start (RPC or turn).
  static Future<void> logReview(
    String action, {
    String? prompt,
    String? display,
    String? actual,
    String? threadId,
    int? conversationId,
    Object? error,
  }) {
    return log(
      'review',
      action,
      fields: <String, Object?>{
        if (prompt != null) 'prompt': prompt,
        if (display != null) 'display': display,
        if (actual != null) 'actual': actual,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (conversationId != null) 'conversationId': conversationId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// Model / effort / service-tier changes.
  static Future<void> logModel(
    String action, {
    String? model,
    String? effort,
    String? serviceTier,
    String? previous,
  }) {
    return log(
      'model',
      action,
      fields: <String, Object?>{
        if (model != null) 'model': model,
        if (effort != null) 'effort': effort,
        if (serviceTier != null) 'serviceTier': serviceTier,
        if (previous != null) 'previous': previous,
      },
    );
  }

  /// B21: Fast mode toggle (UI pref + settings RPC + config fast_mode).
  ///
  /// Matrix: enabled, pref, settingsRpc, configFastMode, activeThreadId.
  static Future<void> logFastSet({
    required bool enabled,
    Object? pref,
    Object? settingsRpc,
    Object? configFastMode,
    String? activeThreadId,
    Object? error,
  }) {
    return log(
      'fast_set',
      enabled ? 'enable' : 'disable',
      fields: <String, Object?>{
        'enabled': enabled,
        if (pref != null) 'pref': pref,
        if (settingsRpc != null) 'settingsRpc': settingsRpc,
        if (configFastMode != null) 'configFastMode': configFastMode,
        if (activeThreadId != null && activeThreadId.isNotEmpty)
          'activeThreadId': activeThreadId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// B21: Turn start payload actually sent (service tier / effort / policy).
  ///
  /// Matrix: serviceTier, effort, approvalPolicy, sandboxType.
  static Future<void> logTurnStart({
    String? serviceTier,
    String? effort,
    String? approvalPolicy,
    String? sandboxType,
    String? threadId,
    int? conversationId,
    String? model,
  }) {
    return log(
      'turn_start',
      'start',
      fields: <String, Object?>{
        if (serviceTier != null) 'serviceTier': serviceTier,
        if (effort != null) 'effort': effort,
        if (approvalPolicy != null) 'approvalPolicy': approvalPolicy,
        if (sandboxType != null) 'sandboxType': sandboxType,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (conversationId != null) 'conversationId': conversationId,
        if (model != null) 'model': model,
      },
    );
  }

  /// B21: Permission mode applied (local state + settings RPC).
  ///
  /// Matrix: mode, approvalPolicy, approvalsReviewer, sandbox, settingsRpc.
  static Future<void> logPermissionSet({
    String? mode,
    String? approvalPolicy,
    String? approvalsReviewer,
    String? sandbox,
    Object? settingsRpc,
    String? threadId,
    Object? error,
  }) {
    return log(
      'permission_set',
      mode == null || mode.isEmpty ? 'set' : 'set:$mode',
      fields: <String, Object?>{
        if (mode != null) 'mode': mode,
        if (approvalPolicy != null) 'approvalPolicy': approvalPolicy,
        if (approvalsReviewer != null) 'approvalsReviewer': approvalsReviewer,
        if (sandbox != null) 'sandbox': sandbox,
        if (settingsRpc != null) 'settingsRpc': settingsRpc,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// B21: Approval prompt shown or user decision.
  ///
  /// [action] typically `prompt` or `decision`.
  /// Matrix: requestId, decision.
  static Future<void> logApproval(
    String action, {
    String? requestId,
    String? decision,
    String? threadId,
    Object? error,
  }) {
    return log(
      'approval',
      action,
      fields: <String, Object?>{
        if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
        if (decision != null) 'decision': decision,
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// B21: Context compact lifecycle.
  ///
  /// [action] typically `start` / `compacted` / `fail` (or matrix compact_*).
  /// Matrix: threadId, error?
  static Future<void> logCompact(
    String action, {
    String? threadId,
    Object? error,
  }) {
    return log(
      'compact',
      action,
      fields: <String, Object?>{
        if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// B21: Reasoning effort change (allowed set + settings RPC).
  ///
  /// Matrix: value, allowedFromModel, settingsRpc.
  /// Prefer this over [logModel] when only effort changes with whitelist info.
  static Future<void> logEffortSet({
    required String value,
    Object? allowedFromModel,
    Object? settingsRpc,
    String? previous,
    String? model,
    Object? error,
  }) {
    return log(
      'effort_set',
      'set',
      fields: <String, Object?>{
        'value': value,
        if (allowedFromModel != null) 'allowedFromModel': allowedFromModel,
        if (settingsRpc != null) 'settingsRpc': settingsRpc,
        if (previous != null) 'previous': previous,
        if (model != null) 'model': model,
        if (error != null) 'error': error.toString(),
      },
    );
  }

  /// Critical errors (catch blocks).
  static Future<void> logError(
    String where,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    final merged = <String, Object?>{
      'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
      ...?fields,
    };
    return log('error', where, fields: merged);
  }

  static void _enqueue(String line) {
    final clipped = line.length > _maxLineChars
        ? '${line.substring(0, _maxLineChars)}…'
        : line;
    if (_queue.length >= _maxQueue) {
      _queue.removeAt(0);
    }
    _queue.add(clipped);
  }

  static Future<void> _flush() async {
    if (!isEnabled || _flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = List<String>.from(_queue);
        _queue.clear();
        final file = await _resolveFile();
        if (file == null) {
          // Put back (bounded) so a later path success can still capture.
          if (_queue.length + batch.length > _maxQueue) {
            final keep = _maxQueue - batch.length;
            if (keep > 0 && _queue.length > keep) {
              _queue.removeRange(0, _queue.length - keep);
            } else if (keep <= 0) {
              _queue.clear();
            }
          }
          _queue.insertAll(0, batch);
          break;
        }
        final payload = '${batch.join('\n')}\n';
        await file.writeAsString(payload, mode: FileMode.append, flush: true);
      }
    } catch (e, st) {
      // Never throw into product paths; keep a breadcrumb in debug console.
      debugPrint('[DebugFileLog] flush failed: $e\n$st');
    } finally {
      _flushing = false;
      if (_queue.isNotEmpty) {
        unawaited(_flush());
      }
    }
  }

  static Future<File?> _resolveFile() {
    return _fileFuture ??= _openLogFile();
  }

  static Future<File?> _openLogFile() async {
    final day = _dayStamp(DateTime.now());
    final fileName = 'omnibot-debug-$day.log';
    final candidates = <Directory>[];

    // 1) Public Download (user-visible without logcat).
    candidates.add(Directory(_downloadRoot));

    // 2) App external storage (Android/data/.../files/OmniBotLogs).
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        candidates.add(Directory('${external.path}/$_dirName'));
      }
    } catch (_) {}

    try {
      final dirs = await getExternalStorageDirectories();
      if (dirs != null) {
        for (final d in dirs) {
          candidates.add(Directory('${d.path}/$_dirName'));
        }
      }
    } catch (_) {}

    // 3) App support (last resort, still on-device).
    try {
      final support = await getApplicationSupportDirectory();
      candidates.add(Directory('${support.path}/$_dirName'));
    } catch (_) {}

    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final file = File('${dir.path}/$fileName');
        if (!await file.exists()) {
          await file.create(recursive: true);
          await file.writeAsString(
            '${_ts()} [debug_file_log] opened path=${file.path}\n',
            mode: FileMode.append,
            flush: true,
          );
        }
        _resolvedPath = file.path;
        return file;
      } catch (e) {
        debugPrint('[DebugFileLog] path failed ${dir.path}: $e');
      }
    }
    _fileFuture = null;
    return null;
  }

  /// Reset cached path (e.g. day rollover / tests).
  static void resetForTest() {
    _queue.clear();
    _fileFuture = null;
    _resolvedPath = null;
    _flushing = false;
  }

  static String _ts() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${three(n.millisecond)}';
  }

  static String _dayStamp(DateTime n) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}';
  }

  static String _formatField(String key, Object? value) {
    if (value == null) return 'null';
    final text = value is String ? value : value.toString();
    final redacted = _redactKeyAware(key, text);
    // Single-line, quote if whitespace / specials.
    final oneLine = redacted.replaceAll(RegExp(r'[\r\n]+'), r'\n');
    if (oneLine.contains(' ') ||
        oneLine.contains('=') ||
        oneLine.contains('"')) {
      return '"${oneLine.replaceAll('"', r'\"')}"';
    }
    return oneLine;
  }

  static final RegExp _secretKey = RegExp(
    r'(api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|'
    r'authorization|bearer|private[_-]?key|client[_-]?secret|openai[_-]?key|'
    r'anthropic[_-]?key|session[_-]?token)',
    caseSensitive: false,
  );

  static final RegExp _inlineSecret = RegExp(
    r'((?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|'
    r'authorization|bearer|private[_-]?key|client[_-]?secret)\s*[:=]\s*)'
    r'([^\s,;"]+)',
    caseSensitive: false,
  );

  static final RegExp _longToken = RegExp(
    r'\b(?:sk-[A-Za-z0-9_-]{8,}|Bearer\s+[A-Za-z0-9._\-+/=]{12,})\b',
    caseSensitive: false,
  );

  static String _redactKeyAware(String key, String value) {
    if (_secretKey.hasMatch(key)) {
      return '***';
    }
    return _redact(value);
  }

  static String _redact(String input) {
    var out = input;
    out = out.replaceAllMapped(_inlineSecret, (m) => '${m[1]}***');
    out = out.replaceAllMapped(_longToken, (m) {
      final raw = m[0] ?? '';
      if (raw.toLowerCase().startsWith('bearer ')) {
        return 'Bearer ***';
      }
      if (raw.length <= 10) return '***';
      return '${raw.substring(0, 6)}***';
    });
    return out;
  }
}
