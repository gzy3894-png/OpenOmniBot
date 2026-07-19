import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Per-turn Codex UI measurements. This tracker is intentionally in-memory;
/// callers decide when to emit the redacted summary to [DebugFileLog].
class CodexPerformanceMetrics {
  static const int _maxFrameSamples = 2048;
  static const int _maxRecentBeforeFrameSamples = 120;

  final _CodexFrameSamples _turnFrames = _CodexFrameSamples();
  final _CodexFrameSamples _recentBeforeFrames = _CodexFrameSamples();
  final _CodexFrameSamples _beforeFrames = _CodexFrameSamples();
  final _CodexFrameSamples _duringFrames = _CodexFrameSamples();
  final _CodexFrameSamples _afterFrames = _CodexFrameSamples();

  int? _turnStartedAtMicros;
  int? _conversationId;
  String? _threadId;
  String? _turnId;
  int _eventCountAtStart = 0;
  int _reduceDurationMicrosAtStart = 0;
  int _uiInvalidationCountAtStart = 0;
  int _coalescedInvalidationCountAtStart = 0;
  int _persistenceQueueCountAtStart = 0;
  int _persistenceFlushCountAtStart = 0;
  int _persistenceDurationMicrosAtStart = 0;
  int _pageRebuildCount = 0;
  bool _collectingAfterTurn = false;

  bool get hasActiveTurn => _turnStartedAtMicros != null;

  void startTurn({
    required int conversationId,
    required String? threadId,
    required String? turnId,
    required int eventCount,
    required int reduceDurationMicros,
    required int uiInvalidationCount,
    required int coalescedInvalidationCount,
    required int persistenceQueueCount,
    required int persistenceFlushCount,
    required int persistenceDurationMicros,
  }) {
    _turnStartedAtMicros = DateTime.now().microsecondsSinceEpoch;
    _conversationId = conversationId;
    _threadId = threadId?.trim();
    _turnId = turnId?.trim();
    _eventCountAtStart = eventCount;
    _reduceDurationMicrosAtStart = reduceDurationMicros;
    _uiInvalidationCountAtStart = uiInvalidationCount;
    _coalescedInvalidationCountAtStart = coalescedInvalidationCount;
    _persistenceQueueCountAtStart = persistenceQueueCount;
    _persistenceFlushCountAtStart = persistenceFlushCount;
    _persistenceDurationMicrosAtStart = persistenceDurationMicros;
    _pageRebuildCount = 0;
    _collectingAfterTurn = false;
    _beforeFrames.replaceWith(_recentBeforeFrames);
    _recentBeforeFrames.clear();
    _duringFrames.clear();
    _afterFrames.clear();
    _turnFrames.clear();
  }

  bool matchesActiveTurn({
    required int conversationId,
    String? threadId,
    String? turnId,
  }) {
    if (!hasActiveTurn || _conversationId != conversationId) {
      return false;
    }
    final expectedThreadId = _threadId ?? '';
    final candidateThreadId = threadId?.trim() ?? '';
    if (expectedThreadId.isNotEmpty &&
        candidateThreadId.isNotEmpty &&
        expectedThreadId != candidateThreadId) {
      return false;
    }
    final expectedTurnId = _turnId ?? '';
    final candidateTurnId = turnId?.trim() ?? '';
    if (expectedTurnId.isNotEmpty) {
      return candidateTurnId.isNotEmpty &&
          expectedTurnId == candidateTurnId;
    }
    return expectedThreadId.isEmpty ||
        candidateThreadId.isEmpty ||
        expectedThreadId == candidateThreadId;
  }

  void recordFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) {
      return;
    }
    if (!hasActiveTurn) {
      _appendTimings(
        _recentBeforeFrames,
        timings,
        maxSamples: _maxRecentBeforeFrameSamples,
      );
      return;
    }
    final phaseFrames = _collectingAfterTurn
        ? _afterFrames
        : _duringFrames;
    _appendTimings(phaseFrames, timings, maxSamples: _maxFrameSamples);
    _appendTimings(_turnFrames, timings, maxSamples: _maxFrameSamples);
  }

  void beginAfterTurn() {
    if (!hasActiveTurn || _collectingAfterTurn) {
      return;
    }
    _collectingAfterTurn = true;
  }

  void _appendTimings(
    _CodexFrameSamples destination,
    List<FrameTiming> timings, {
    required int maxSamples,
  }) {
    for (final timing in timings) {
      _appendBounded(
        destination.buildMicros,
        timing.buildDuration.inMicroseconds,
        maxSamples: maxSamples,
      );
      _appendBounded(
        destination.rasterMicros,
        timing.rasterDuration.inMicroseconds,
        maxSamples: maxSamples,
      );
      _appendBounded(
        destination.totalMicros,
        timing.totalSpan.inMicroseconds,
        maxSamples: maxSamples,
      );
    }
  }

  void recordPageRebuild() {
    if (hasActiveTurn) {
      _pageRebuildCount += 1;
    }
  }

  Map<String, Object?> finishTurn({
    required int eventCount,
    required int uiInvalidationCount,
    required int coalescedInvalidationCount,
    required int reduceDurationMicros,
    required int persistenceQueueCount,
    required int persistenceFlushCount,
    required int persistenceDurationMicros,
    required int messageCount,
  }) {
    final startedAt = _turnStartedAtMicros;
    final now = DateTime.now().microsecondsSinceEpoch;
    final elapsedMicros = startedAt == null ? 0 : now - startedAt;
    final events = (eventCount - _eventCountAtStart).clamp(0, eventCount);
    final invalidations =
        (uiInvalidationCount - _uiInvalidationCountAtStart).clamp(
          0,
          uiInvalidationCount,
        );
    final coalesced =
        (coalescedInvalidationCount - _coalescedInvalidationCountAtStart)
            .clamp(0, coalescedInvalidationCount);
    final persistQueued =
        (persistenceQueueCount - _persistenceQueueCountAtStart).clamp(
          0,
          persistenceQueueCount,
        );
    final persistFlushed =
        (persistenceFlushCount - _persistenceFlushCountAtStart).clamp(
          0,
          persistenceFlushCount,
        );
    final persistMicros =
        (persistenceDurationMicros - _persistenceDurationMicrosAtStart).clamp(
          0,
          persistenceDurationMicros,
        );
    final eventRate = elapsedMicros <= 0
        ? 0.0
        : events * Duration.microsecondsPerSecond / elapsedMicros;
    final reduceMicros =
        (reduceDurationMicros - _reduceDurationMicrosAtStart).clamp(
          0,
          reduceDurationMicros,
        );

    final result = <String, Object?>{
      'durationMs': elapsedMicros / 1000,
      'conversationId': _conversationId,
      if ((_threadId ?? '').isNotEmpty) 'threadId': _threadId,
      if ((_turnId ?? '').isNotEmpty) 'turnId': _turnId,
      'events': events,
      'eventsPerSecond': double.parse(eventRate.toStringAsFixed(2)),
      'reduceDurationMs': reduceMicros / 1000,
      'uiInvalidations': invalidations,
      'coalescedInvalidations': coalesced,
      'pageRebuilds': _pageRebuildCount,
      'messageCount': messageCount,
      'messageCountBucket': _messageCountBucket(messageCount),
      'persistQueued': persistQueued,
      'persistFlushed': persistFlushed,
      'persistDurationMs': persistMicros / 1000,
      ..._frameSummaryFields(_turnFrames),
      ..._frameSummaryFields(_beforeFrames, prefix: 'before'),
      ..._frameSummaryFields(_duringFrames, prefix: 'during'),
      ..._frameSummaryFields(_afterFrames, prefix: 'after'),
    };
    reset();
    return result;
  }

  @visibleForTesting
  void reset() {
    _turnStartedAtMicros = null;
    _conversationId = null;
    _threadId = null;
    _turnId = null;
    _eventCountAtStart = 0;
    _reduceDurationMicrosAtStart = 0;
    _uiInvalidationCountAtStart = 0;
    _coalescedInvalidationCountAtStart = 0;
    _persistenceQueueCountAtStart = 0;
    _persistenceFlushCountAtStart = 0;
    _persistenceDurationMicrosAtStart = 0;
    _pageRebuildCount = 0;
    _collectingAfterTurn = false;
    _turnFrames.clear();
    _recentBeforeFrames.clear();
    _beforeFrames.clear();
    _duringFrames.clear();
    _afterFrames.clear();
  }

  void _appendBounded(
    List<int> samples,
    int value, {
    required int maxSamples,
  }) {
    if (samples.length >= maxSamples) {
      samples.removeAt(0);
    }
    samples.add(value);
  }

  Map<String, Object?> _frameSummaryFields(
    _CodexFrameSamples samples, {
    String prefix = '',
  }) {
    String field(String name) {
      if (prefix.isEmpty) {
        return name;
      }
      return '$prefix${name[0].toUpperCase()}${name.substring(1)}';
    }

    return <String, Object?>{
      field('frameCount'): samples.totalMicros.length,
      field('buildP50Ms'): _percentileMillis(samples.buildMicros, 0.50),
      field('buildP95Ms'): _percentileMillis(samples.buildMicros, 0.95),
      field('buildP99Ms'): _percentileMillis(samples.buildMicros, 0.99),
      field('rasterP50Ms'): _percentileMillis(samples.rasterMicros, 0.50),
      field('rasterP95Ms'): _percentileMillis(samples.rasterMicros, 0.95),
      field('rasterP99Ms'): _percentileMillis(samples.rasterMicros, 0.99),
      field('frameP50Ms'): _percentileMillis(samples.totalMicros, 0.50),
      field('frameP95Ms'): _percentileMillis(samples.totalMicros, 0.95),
      field('frameP99Ms'): _percentileMillis(samples.totalMicros, 0.99),
      field('framesOver16_7Ms'):
          samples.totalMicros.where((value) => value > 16667).length,
      field('framesOver32Ms'):
          samples.totalMicros.where((value) => value > 32000).length,
    };
  }

  String _messageCountBucket(int messageCount) {
    if (messageCount <= 0) {
      return '0';
    }
    if (messageCount <= 20) {
      return '1-20';
    }
    if (messageCount <= 50) {
      return '21-50';
    }
    if (messageCount <= 100) {
      return '51-100';
    }
    if (messageCount <= 200) {
      return '101-200';
    }
    if (messageCount <= 500) {
      return '201-500';
    }
    return '501+';
  }

  double _percentileMillis(List<int> source, double percentile) {
    if (source.isEmpty) {
      return 0;
    }
    final sorted = List<int>.from(source)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return double.parse((sorted[index] / 1000).toStringAsFixed(3));
  }
}

class _CodexFrameSamples {
  final List<int> buildMicros = <int>[];
  final List<int> rasterMicros = <int>[];
  final List<int> totalMicros = <int>[];

  void replaceWith(_CodexFrameSamples source) {
    buildMicros
      ..clear()
      ..addAll(source.buildMicros);
    rasterMicros
      ..clear()
      ..addAll(source.rasterMicros);
    totalMicros
      ..clear()
      ..addAll(source.totalMicros);
  }

  void clear() {
    buildMicros.clear();
    rasterMicros.clear();
    totalMicros.clear();
  }
}
