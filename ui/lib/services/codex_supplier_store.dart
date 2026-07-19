import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/services/storage_service.dart';

/// Default reasoning efforts for every Codex supplier model entry.
const List<String> kCodexDefaultEfforts = <String>[
  'low',
  'medium',
  'high',
  'xhigh',
];

/// One model row owned by a Codex supplier (application library).
class CodexSupplierModelEntry {
  const CodexSupplierModelEntry({
    required this.id,
    this.enabled = true,
    this.displayName = '',
    this.defaultEffort = 'medium',
    this.supportedEfforts = kCodexDefaultEfforts,
  });

  final String id;
  final bool enabled;
  final String displayName;
  final String defaultEffort;
  final List<String> supportedEfforts;

  String get label {
    final name = displayName.trim();
    return name.isEmpty ? id : name;
  }

  CodexSupplierModelEntry copyWith({
    String? id,
    bool? enabled,
    String? displayName,
    String? defaultEffort,
    List<String>? supportedEfforts,
  }) {
    return CodexSupplierModelEntry(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      displayName: displayName ?? this.displayName,
      defaultEffort: defaultEffort ?? this.defaultEffort,
      supportedEfforts: supportedEfforts ?? this.supportedEfforts,
    );
  }

  factory CodexSupplierModelEntry.fromMap(Map<dynamic, dynamic>? map) {
    final id = (map?['id'] ?? map?['slug'] ?? '').toString().trim();
    final rawEfforts = map?['supportedEfforts'] ?? map?['supported_reasoning_levels'];
    final efforts = <String>[];
    if (rawEfforts is List) {
      for (final item in rawEfforts) {
        if (item is Map) {
          final effort = (item['effort'] ?? '').toString().trim();
          if (effort.isNotEmpty) {
            efforts.add(effort);
          }
        } else {
          final effort = item?.toString().trim() ?? '';
          if (effort.isNotEmpty) {
            efforts.add(effort);
          }
        }
      }
    }
    final defaultEffort = (map?['defaultEffort'] ??
            map?['default_reasoning_level'] ??
            'medium')
        .toString()
        .trim();
    return CodexSupplierModelEntry(
      id: id,
      enabled: map?['enabled'] != false,
      displayName: (map?['displayName'] ?? map?['display_name'] ?? id)
          .toString()
          .trim(),
      defaultEffort: defaultEffort.isEmpty ? 'medium' : defaultEffort,
      supportedEfforts: efforts.isEmpty
          ? kCodexDefaultEfforts
          : List<String>.unmodifiable(efforts),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'enabled': enabled,
      'displayName': displayName,
      'defaultEffort': defaultEffort,
      'supportedEfforts': supportedEfforts,
    };
  }
}

/// Codex-private supplier record. Never shared with Agent provider profiles.
class CodexSupplierRecord {
  const CodexSupplierRecord({
    required this.id,
    required this.baseUrl,
    required this.apiKey,
    this.memoName = '',
    this.models = const <CodexSupplierModelEntry>[],
    this.activeModelId = '',
    this.activeEffort = 'medium',
    this.updatedAt = 0,
  });

  final String id;
  final String memoName;
  final String baseUrl;
  final String apiKey;
  final List<CodexSupplierModelEntry> models;
  final String activeModelId;
  final String activeEffort;
  final int updatedAt;

  String get displayName {
    final memo = memoName.trim();
    if (memo.isNotEmpty) {
      return memo;
    }
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    if (host.isNotEmpty) {
      return host;
    }
    return id;
  }

  List<CodexSupplierModelEntry> get enabledModels => models
      .where((item) => item.enabled && item.id.trim().isNotEmpty)
      .toList(growable: false);

  List<String> get enabledModelIds =>
      enabledModels.map((item) => item.id).toList(growable: false);

  bool get hasEnabledModel => enabledModelIds.isNotEmpty;

  CodexSupplierRecord copyWith({
    String? id,
    String? memoName,
    String? baseUrl,
    String? apiKey,
    List<CodexSupplierModelEntry>? models,
    String? activeModelId,
    String? activeEffort,
    int? updatedAt,
  }) {
    return CodexSupplierRecord(
      id: id ?? this.id,
      memoName: memoName ?? this.memoName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      activeModelId: activeModelId ?? this.activeModelId,
      activeEffort: activeEffort ?? this.activeEffort,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Ensure active model is among enabled models when possible.
  CodexSupplierRecord normalized() {
    final cleanedModels = <CodexSupplierModelEntry>[];
    final seen = <String>{};
    for (final model in models) {
      final id = model.id.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      cleanedModels.add(model.copyWith(id: id));
    }
    final enabledIds = cleanedModels
        .where((item) => item.enabled)
        .map((item) => item.id)
        .toSet();
    var nextActive = activeModelId.trim();
    if (nextActive.isEmpty || !enabledIds.contains(nextActive)) {
      nextActive = enabledIds.isEmpty ? '' : enabledIds.first;
    }
    var effort = activeEffort.trim().toLowerCase();
    if (effort.isEmpty || !kCodexDefaultEfforts.contains(effort)) {
      CodexSupplierModelEntry? match;
      for (final model in cleanedModels) {
        if (model.id == nextActive) {
          match = model;
          break;
        }
      }
      effort = match?.defaultEffort.trim().toLowerCase() ?? 'medium';
      if (!kCodexDefaultEfforts.contains(effort)) {
        effort = 'medium';
      }
    }
    return copyWith(
      models: List<CodexSupplierModelEntry>.unmodifiable(cleanedModels),
      activeModelId: nextActive,
      activeEffort: effort,
    );
  }

  factory CodexSupplierRecord.fromMap(Map<dynamic, dynamic>? map) {
    final models = <CodexSupplierModelEntry>[];
    final rawModels = map?['models'];
    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is Map) {
          final entry = CodexSupplierModelEntry.fromMap(item);
          if (entry.id.isNotEmpty) {
            models.add(entry);
          }
        } else if (item != null) {
          final id = item.toString().trim();
          if (id.isNotEmpty) {
            models.add(CodexSupplierModelEntry(id: id));
          }
        }
      }
    }
    return CodexSupplierRecord(
      id: (map?['id'] ?? '').toString().trim(),
      memoName: (map?['memoName'] ?? map?['name'] ?? '').toString().trim(),
      baseUrl: (map?['baseUrl'] ?? '').toString().trim(),
      apiKey: (map?['apiKey'] ?? '').toString(),
      models: List<CodexSupplierModelEntry>.unmodifiable(models),
      activeModelId: (map?['activeModelId'] ?? '').toString().trim(),
      activeEffort: (map?['activeEffort'] ?? 'medium').toString().trim(),
      updatedAt: _readInt(map?['updatedAt']),
    ).normalized();
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'memoName': memoName,
      'baseUrl': baseUrl,
      // apiKey is application-private storage; never log this map.
      'apiKey': apiKey,
      'models': models.map((item) => item.toMap()).toList(growable: false),
      'activeModelId': activeModelId,
      'activeEffort': activeEffort,
      'updatedAt': updatedAt,
    };
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Full Codex supplier library snapshot.
class CodexSupplierLibrary {
  const CodexSupplierLibrary({
    this.activeSupplierId = '',
    this.suppliers = const <CodexSupplierRecord>[],
  });

  final String activeSupplierId;
  final List<CodexSupplierRecord> suppliers;

  CodexSupplierRecord? get activeSupplier {
    final id = activeSupplierId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final supplier in suppliers) {
      if (supplier.id == id) {
        return supplier;
      }
    }
    return null;
  }

  CodexSupplierRecord? find(String supplierId) {
    final id = supplierId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final supplier in suppliers) {
      if (supplier.id == id) {
        return supplier;
      }
    }
    return null;
  }

  CodexSupplierLibrary copyWith({
    String? activeSupplierId,
    List<CodexSupplierRecord>? suppliers,
  }) {
    return CodexSupplierLibrary(
      activeSupplierId: activeSupplierId ?? this.activeSupplierId,
      suppliers: suppliers ?? this.suppliers,
    );
  }

  factory CodexSupplierLibrary.fromMap(Map<dynamic, dynamic>? map) {
    final suppliers = <CodexSupplierRecord>[];
    final raw = map?['suppliers'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final record = CodexSupplierRecord.fromMap(item);
          if (record.id.isNotEmpty) {
            suppliers.add(record);
          }
        }
      }
    }
    var activeId = (map?['activeSupplierId'] ?? '').toString().trim();
    if (activeId.isNotEmpty &&
        !suppliers.any((item) => item.id == activeId)) {
      activeId = '';
    }
    if (activeId.isEmpty && suppliers.isNotEmpty) {
      activeId = suppliers.first.id;
    }
    return CodexSupplierLibrary(
      activeSupplierId: activeId,
      suppliers: List<CodexSupplierRecord>.unmodifiable(suppliers),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'activeSupplierId': activeSupplierId,
      'suppliers':
          suppliers.map((item) => item.toMap()).toList(growable: false),
    };
  }
}

/// Result of validating a supplier before switch/apply.
class CodexSupplierValidation {
  const CodexSupplierValidation._(this.reason);

  const CodexSupplierValidation.ok() : reason = '';

  final String reason;

  bool get isOk => reason.isEmpty;
}

/// Case-insensitive filter of model entries by id / displayName.
///
/// Empty [query] returns the input list unchanged (still non-growable).
List<CodexSupplierModelEntry> filterCodexSupplierModels(
  Iterable<CodexSupplierModelEntry> models,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return List<CodexSupplierModelEntry>.unmodifiable(models);
  }
  return models
      .where((item) {
        final id = item.id.toLowerCase();
        final name = item.displayName.trim().toLowerCase();
        return id.contains(q) || name.contains(q);
      })
      .toList(growable: false);
}

/// Codex-private supplier library.
///
/// Physically isolated from [ModelProviderConfigService] Agent profiles.
/// Runtime always maps the active supplier onto fixed internal `omnimind`.
class CodexSupplierStore {
  CodexSupplierStore._();

  static const String storageKey = 'codex_suppliers_v1';
  static const String migrationFlagKey = 'codex_suppliers_migrated_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> Function()? _migrateHook;
  static CodexSupplierLibrary? _memoryFallback;
  static bool _memoryMigrated = false;
  static bool _debugForceMemoryOnly = false;

  /// Test seam: replace migration body (bypasses once-flag; used for isolation).
  @visibleForTesting
  static void debugSetMigrateHook(Future<void> Function()? hook) {
    _migrateHook = hook;
  }

  /// Test seam: force write/read to skip Storage (simulates Storage not init).
  @visibleForTesting
  static void debugForceMemoryOnly(bool enabled) {
    _debugForceMemoryOnly = enabled;
  }

  /// Test seam: clear in-memory fallback / migration flag used when Storage is
  /// unavailable or in unit tests between cases.
  @visibleForTesting
  static void debugResetMemory() {
    _memoryFallback = null;
    _memoryMigrated = false;
    _migrateHook = null;
    _debugForceMemoryOnly = false;
  }

  static CodexSupplierLibrary read() {
    if (!_debugForceMemoryOnly) {
      try {
        final raw = StorageService.getString(storageKey, defaultValue: '');
        if (raw != null && raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            return CodexSupplierLibrary.fromMap(decoded);
          }
        }
      } catch (_) {
        // Fall through to memory fallback / empty.
      }
    }
    return _memoryFallback ?? const CodexSupplierLibrary();
  }

  static Future<void> write(CodexSupplierLibrary library) async {
    final normalized = CodexSupplierLibrary(
      activeSupplierId: library.activeSupplierId,
      suppliers: library.suppliers
          .map((item) => item.normalized())
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
    );
    final payload = jsonEncode(normalized.toMap());
    try {
      if (_debugForceMemoryOnly) {
        throw StateError('debugForceMemoryOnly');
      }
      final stored = await StorageService.setString(storageKey, payload);
      if (!stored) {
        throw StateError('Unable to persist Codex supplier library');
      }
      _memoryFallback = null;
    } catch (_) {
      // Unit tests may run without StorageService.init; keep an in-memory copy.
      _memoryFallback = normalized;
    }
    revision.value += 1;
  }

  /// One-shot copy from legacy `codex_provider_state_v1` + Agent profiles.
  ///
  /// After the migration flag is set, Agent profile changes never flow back.
  /// Injects exist so unit tests never need the Agent runtime write path.
  static Future<void> ensureMigrated({
    Future<ModelProviderProfilesPayload> Function()? listProfiles,
    Future<CodexLocalConfig> Function()? readLocalConfig,
    Future<List<ProviderModelOption>> Function(
      ModelProviderProfileSummary profile,
    )? getStoredModelsForProfile,
    CodexProviderState Function()? readLegacyProviderState,
  }) async {
    if (_migrateHook != null) {
      await _migrateHook!.call();
      return;
    }
    if (_memoryMigrated) {
      return;
    }
    try {
      if (StorageService.getBool(migrationFlagKey, defaultValue: false) ==
          true) {
        _memoryMigrated = true;
        return;
      }
    } catch (_) {
      // Storage unavailable: still attempt one in-memory migration.
    }

    final existing = read();
    if (existing.suppliers.isNotEmpty) {
      await _markMigrated();
      return;
    }

    final migrated = <CodexSupplierRecord>[];
    String activeId = '';

    // 1) Legacy selection + Agent profile copy (one-shot, no ongoing sync).
    try {
      final legacy = (readLegacyProviderState ??
          ModelProviderConfigService.readCodexProviderState)();
      final profiles =
          await (listProfiles ?? ModelProviderConfigService.listProfiles)();
      final profileById = <String, ModelProviderProfileSummary>{
        for (final profile in profiles.profiles) profile.id: profile,
      };

      Future<CodexSupplierRecord?> copyProfile(
        ModelProviderProfileSummary profile,
      ) async {
        final base =
            ModelProviderConfigService.normalizeApiBase(profile.baseUrl) ??
                profile.baseUrl.trim();
        if (base.isEmpty || profile.apiKey.trim().isEmpty) {
          return null;
        }
        List<ProviderModelOption> stored = const <ProviderModelOption>[];
        try {
          if (getStoredModelsForProfile != null) {
            stored = await getStoredModelsForProfile(profile);
          } else {
            stored = await ModelProviderConfigService
                .getStoredModelOptionsForProfile(
              profile.id,
              profile: profile,
            );
          }
        } catch (_) {}
        final models = stored
            .map(
              (item) => CodexSupplierModelEntry(
                id: item.id,
                enabled: true,
                displayName: item.displayName,
              ),
            )
            .toList(growable: false);
        final remembered = legacy.currentModels[profile.id] ?? '';
        final activeModel = models.any((item) => item.id == remembered)
            ? remembered
            : (models.isEmpty ? '' : models.first.id);
        return CodexSupplierRecord(
          id: profile.id.trim().isEmpty
              ? _newId()
              : profile.id.trim(),
          memoName: profile.name.trim(),
          baseUrl: base,
          apiKey: profile.apiKey,
          models: models,
          activeModelId: activeModel,
          activeEffort: 'medium',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ).normalized();
      }

      if (legacy.activeProviderId.trim().isNotEmpty) {
        final active = profileById[legacy.activeProviderId];
        if (active != null) {
          final record = await copyProfile(active);
          if (record != null) {
            migrated.add(record);
            activeId = record.id;
          }
        }
      }

      // Also copy other remembered providers so A/B history is not lost once.
      for (final entry in legacy.currentModels.entries) {
        if (migrated.any((item) => item.id == entry.key)) {
          continue;
        }
        final profile = profileById[entry.key];
        if (profile == null) {
          continue;
        }
        final record = await copyProfile(profile);
        if (record != null) {
          migrated.add(record);
        }
      }
    } catch (_) {
      // Migration is best-effort.
    }

    // 2) Fallback: current Native local config as a single supplier.
    if (migrated.isEmpty) {
      try {
        final config =
            await (readLocalConfig ?? CodexAppServerService.readLocalConfig)();
        final base =
            ModelProviderConfigService.normalizeApiBase(config.baseUrl) ??
                config.baseUrl.trim();
        if (base.isNotEmpty && config.apiKey.trim().isNotEmpty) {
          final modelId = config.model.trim();
          final models = modelId.isEmpty
              ? const <CodexSupplierModelEntry>[]
              : <CodexSupplierModelEntry>[
                  CodexSupplierModelEntry(id: modelId, enabled: true),
                ];
          final id = _newId();
          migrated.add(
            CodexSupplierRecord(
              id: id,
              memoName: 'Migrated',
              baseUrl: base,
              apiKey: config.apiKey,
              models: models,
              activeModelId: modelId,
              activeEffort: config.modelReasoningEffort.trim().isEmpty
                  ? 'medium'
                  : config.modelReasoningEffort.trim(),
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ).normalized(),
          );
          activeId = id;
        }
      } catch (_) {}
    }

    if (migrated.isNotEmpty) {
      await write(
        CodexSupplierLibrary(
          activeSupplierId: activeId.isEmpty ? migrated.first.id : activeId,
          suppliers: migrated,
        ),
      );
    }
    await _markMigrated();
  }

  static Future<void> _markMigrated() async {
    _memoryMigrated = true;
    try {
      await StorageService.setBool(migrationFlagKey, true);
    } catch (_) {
      // Memory flag alone is enough for Storage-less unit tests.
    }
  }

  static CodexSupplierValidation validateForSwitch(CodexSupplierRecord supplier) {
    final id = supplier.id.trim();
    if (id.isEmpty) {
      return const CodexSupplierValidation._('Supplier has no stable id');
    }
    final base =
        ModelProviderConfigService.normalizeApiBase(supplier.baseUrl) ??
            supplier.baseUrl.trim();
    if (base.isEmpty) {
      return const CodexSupplierValidation._('API Base URL is invalid');
    }
    final uri = Uri.tryParse(base);
    if (uri == null || uri.hasQuery || uri.hasFragment) {
      return const CodexSupplierValidation._(
        'API Base URL must not include query or fragment',
      );
    }
    if (supplier.apiKey.trim().isEmpty) {
      return const CodexSupplierValidation._('API Key is missing');
    }
    final enabled = supplier.enabledModelIds;
    if (enabled.isEmpty) {
      return const CodexSupplierValidation._(
        'Enable at least one model for this supplier',
      );
    }
    final active = supplier.activeModelId.trim();
    if (active.isEmpty || !enabled.contains(active)) {
      return const CodexSupplierValidation._(
        'Active model must be one of the enabled models',
      );
    }
    return const CodexSupplierValidation.ok();
  }

  static Future<CodexSupplierRecord> upsert(CodexSupplierRecord record) async {
    await ensureMigrated();
    final library = read();
    final next = record.normalized().copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final suppliers = [...library.suppliers];
    final index = suppliers.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      suppliers[index] = next;
    } else {
      suppliers.add(next);
    }
    final activeId = library.activeSupplierId.trim().isEmpty
        ? next.id
        : library.activeSupplierId;
    await write(
      CodexSupplierLibrary(
        activeSupplierId: activeId,
        suppliers: suppliers,
      ),
    );
    return next;
  }

  static Future<void> delete(String supplierId) async {
    await ensureMigrated();
    final id = supplierId.trim();
    final library = read();
    final suppliers =
        library.suppliers.where((item) => item.id != id).toList(growable: false);
    var activeId = library.activeSupplierId;
    if (activeId == id) {
      activeId = suppliers.isEmpty ? '' : suppliers.first.id;
    }
    await write(
      CodexSupplierLibrary(
        activeSupplierId: activeId,
        suppliers: suppliers,
      ),
    );
  }

  static Future<void> setActiveSupplierId(String supplierId) async {
    await ensureMigrated();
    final library = read();
    final id = supplierId.trim();
    if (id.isNotEmpty && library.find(id) == null) {
      throw StateError('Unknown Codex supplier: $id');
    }
    await write(library.copyWith(activeSupplierId: id));
  }

  static Future<CodexSupplierRecord> mergeFetchedModels({
    required String supplierId,
    required List<String> remoteModelIds, {
    bool defaultEnableNew = true,
  }) async {
    await ensureMigrated();
    final library = read();
    final existing = library.find(supplierId);
    if (existing == null) {
      throw StateError('Unknown Codex supplier: $supplierId');
    }
    final byId = <String, CodexSupplierModelEntry>{
      for (final model in existing.models) model.id: model,
    };
    for (final rawId in remoteModelIds) {
      final id = rawId.trim();
      if (id.isEmpty) {
        continue;
      }
      final prior = byId[id];
      if (prior == null) {
        byId[id] = CodexSupplierModelEntry(
          id: id,
          enabled: defaultEnableNew,
          displayName: id,
        );
      } else {
        // Keep user's enabled flag; refresh display default if empty.
        byId[id] = prior.copyWith(
          displayName: prior.displayName.trim().isEmpty ? id : prior.displayName,
        );
      }
    }
    final merged = existing
        .copyWith(
          models: byId.values.toList(growable: false),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        )
        .normalized();
    await upsert(merged);
    return merged;
  }

  static Future<CodexSupplierRecord> setModelEnabled({
    required String supplierId,
    required String modelId,
    required bool enabled,
  }) async {
    final library = read();
    final existing = library.find(supplierId);
    if (existing == null) {
      throw StateError('Unknown Codex supplier: $supplierId');
    }
    final models = existing.models.map((item) {
      if (item.id == modelId.trim()) {
        return item.copyWith(enabled: enabled);
      }
      return item;
    }).toList(growable: false);
    return upsert(existing.copyWith(models: models));
  }

  static Future<CodexSupplierRecord> setVisibleModelsEnabled({
    required String supplierId,
    required Iterable<String> visibleModelIds,
    required bool enabled,
  }) async {
    final visible = visibleModelIds.map((item) => item.trim()).toSet();
    final library = read();
    final existing = library.find(supplierId);
    if (existing == null) {
      throw StateError('Unknown Codex supplier: $supplierId');
    }
    final models = existing.models.map((item) {
      if (visible.contains(item.id)) {
        return item.copyWith(enabled: enabled);
      }
      return item;
    }).toList(growable: false);
    return upsert(existing.copyWith(models: models));
  }

  static Future<CodexSupplierRecord> invertVisibleModels({
    required String supplierId,
    required Iterable<String> visibleModelIds,
  }) async {
    final visible = visibleModelIds.map((item) => item.trim()).toSet();
    final library = read();
    final existing = library.find(supplierId);
    if (existing == null) {
      throw StateError('Unknown Codex supplier: $supplierId');
    }
    final models = existing.models.map((item) {
      if (visible.contains(item.id)) {
        return item.copyWith(enabled: !item.enabled);
      }
      return item;
    }).toList(growable: false);
    return upsert(existing.copyWith(models: models));
  }

  static Future<CodexSupplierRecord> addManualModel({
    required String supplierId,
    required String modelId, {
    bool enabled = true,
  }) async {
    final id = modelId.trim();
    if (id.isEmpty) {
      throw ArgumentError('modelId is empty');
    }
    final library = read();
    final existing = library.find(supplierId);
    if (existing == null) {
      throw StateError('Unknown Codex supplier: $supplierId');
    }
    final models = [...existing.models];
    final index = models.indexWhere((item) => item.id == id);
    if (index >= 0) {
      models[index] = models[index].copyWith(enabled: enabled);
    } else {
      models.add(CodexSupplierModelEntry(id: id, enabled: enabled));
    }
    return upsert(existing.copyWith(models: models));
  }

  static String newSupplierId() => _newId();

  static String _newId() {
    final millis = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'codex-supplier-$millis';
  }
}
