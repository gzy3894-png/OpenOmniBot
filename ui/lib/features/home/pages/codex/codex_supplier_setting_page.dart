import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/codex_supplier_store.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/settings_section_title.dart';

/// Codex-private supplier library manager.
///
/// Form fields are limited to memo (optional) + API Base URL + API Key.
/// Protocol is fixed to Responses (no UI control). Model list supports
/// search + bulk enable of the visible set. Never logs API keys.
class CodexSupplierSettingPage extends StatefulWidget {
  const CodexSupplierSettingPage({
    super.key,
    this.listModelsOverride,
  });

  /// Test seam for [CodexAppServerService.listModelsFromProviderHttp].
  final Future<CodexHttpModelsResult> Function({
    required String baseUrl,
    required String apiKey,
  })?
  listModelsOverride;

  @override
  State<CodexSupplierSettingPage> createState() =>
      _CodexSupplierSettingPageState();
}

class _CodexSupplierSettingPageState extends State<CodexSupplierSettingPage> {
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualModelController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isFetchingModels = false;
  bool _obscureApiKey = true;
  bool _syncingControllers = false;
  String _selectedSupplierId = '';
  String _searchQuery = '';
  String? _statusMessage;
  bool _statusIsError = false;

  CodexSupplierLibrary _library = const CodexSupplierLibrary();

  bool get _isDarkTheme => context.isDarkTheme;
  Color get _pageBackground =>
      _isDarkTheme ? context.omniPalette.pageBackground : AppColors.background;
  Color get _cardColor =>
      _isDarkTheme ? context.omniPalette.surfacePrimary : Colors.white;
  Color get _primaryTextColor =>
      _isDarkTheme ? context.omniPalette.textPrimary : AppColors.text;
  Color get _secondaryTextColor =>
      _isDarkTheme ? context.omniPalette.textSecondary : AppColors.text70;
  Color get _borderColor =>
      _isDarkTheme ? context.omniPalette.borderSubtle : AppColors.borderStandard;
  Color get _chipBg =>
      _isDarkTheme ? context.omniPalette.surfaceSecondary : AppColors.background;
  Color get _accentColor =>
      _isDarkTheme ? context.omniPalette.accentPrimary : AppColors.buttonPrimary;
  static const Color _successColor = Color(0xFF3DD68C);

  CodexSupplierRecord? get _selectedSupplier {
    final id = _selectedSupplierId.trim();
    if (id.isEmpty) {
      return null;
    }
    return _library.find(id);
  }

  List<CodexSupplierModelEntry> get _allModels =>
      _selectedSupplier?.models ?? const <CodexSupplierModelEntry>[];

  List<CodexSupplierModelEntry> get _visibleModels {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _allModels;
    }
    return _allModels
        .where((model) {
          final id = model.id.toLowerCase();
          final label = model.label.toLowerCase();
          return id.contains(query) || label.contains(query);
        })
        .toList(growable: false);
  }

  int get _enabledCount =>
      _allModels.where((item) => item.enabled).length;

  int get _visibleCount => _visibleModels.length;

  int get _totalCount => _allModels.length;

  @override
  void initState() {
    super.initState();
    CodexSupplierStore.revision.addListener(_onStoreRevision);
    _searchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    CodexSupplierStore.revision.removeListener(_onStoreRevision);
    _memoController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _searchController.dispose();
    _manualModelController.dispose();
    super.dispose();
  }

  void _onStoreRevision() {
    if (!mounted || _isSaving || _isFetchingModels) {
      return;
    }
    _reloadFromStore(syncControllers: true);
  }

  Future<void> _bootstrap() async {
    try {
      await CodexSupplierStore.ensureMigrated();
    } catch (_) {
      // Migration is best-effort; page still works with empty library.
    }
    if (!mounted) {
      return;
    }
    _reloadFromStore(syncControllers: true);
    setState(() {
      _isLoading = false;
    });
  }

  void _reloadFromStore({required bool syncControllers}) {
    final library = CodexSupplierStore.read();
    var selectedId = _selectedSupplierId.trim();
    if (selectedId.isEmpty || library.find(selectedId) == null) {
      selectedId = library.activeSupplierId.trim();
    }
    if (selectedId.isEmpty && library.suppliers.isNotEmpty) {
      selectedId = library.suppliers.first.id;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _library = library;
      _selectedSupplierId = selectedId;
    });
    if (syncControllers) {
      _syncControllersFromSelected();
    }
  }

  void _syncControllersFromSelected() {
    final supplier = _selectedSupplier;
    _syncingControllers = true;
    if (supplier == null) {
      _memoController.text = '';
      _baseUrlController.text = '';
      _apiKeyController.text = '';
    } else {
      _memoController.text = supplier.memoName;
      _baseUrlController.text = supplier.baseUrl;
      _apiKeyController.text = supplier.apiKey;
    }
    _syncingControllers = false;
  }

  void _selectSupplier(String supplierId) {
    final id = supplierId.trim();
    if (id.isEmpty || id == _selectedSupplierId) {
      return;
    }
    setState(() {
      _selectedSupplierId = id;
      _statusMessage = null;
    });
    _syncControllersFromSelected();
  }

  Future<void> _createSupplier() async {
    final id = CodexSupplierStore.newSupplierId();
    final created = CodexSupplierRecord(
      id: id,
      memoName: '',
      baseUrl: '',
      apiKey: '',
      models: const <CodexSupplierModelEntry>[],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });
    try {
      await CodexSupplierStore.upsert(created);
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      setState(() {
        _selectedSupplierId = id;
        _isSaving = false;
      });
      _syncControllersFromSelected();
      showToast('已新增供应商，请填写 API Base 与 Key', type: ToastType.info);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _statusIsError = true;
        _statusMessage = '新增失败';
      });
      showToast('新增失败', type: ToastType.error);
    }
  }

  Future<void> _saveSelected() async {
    final existing = _selectedSupplier;
    if (existing == null) {
      showToast('请先选择或新增供应商', type: ToastType.warning);
      return;
    }
    final baseRaw = _baseUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final memo = _memoController.text.trim();
    final normalized =
        ModelProviderConfigService.normalizeApiBase(baseRaw) ?? baseRaw;
    if (normalized.isEmpty) {
      showToast('请填写 API Base URL', type: ToastType.warning);
      return;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      showToast('API Base URL 无效', type: ToastType.warning);
      return;
    }
    if (uri.hasQuery || uri.hasFragment) {
      showToast('API Base URL 不能包含 query 或 fragment', type: ToastType.warning);
      return;
    }
    if (key.isEmpty) {
      showToast('请填写 API Key', type: ToastType.warning);
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });
    try {
      final next = existing.copyWith(
        memoName: memo,
        baseUrl: normalized,
        apiKey: key,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await CodexSupplierStore.upsert(next);
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: true);
      setState(() {
        _isSaving = false;
        _statusIsError = false;
        _statusMessage = '已保存';
      });
      showToast('已保存', type: ToastType.success);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _statusIsError = true;
        _statusMessage = '保存失败';
      });
      showToast('保存失败', type: ToastType.error);
    }
  }

  Future<void> _deleteSelected() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除供应商'),
          content: Text(
            '确定删除「${supplier.displayName}」？\n仅影响 Codex 私有库，不会改动 Agent 供应商。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await CodexSupplierStore.delete(supplier.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedSupplierId = '';
        _isSaving = false;
        _statusMessage = null;
      });
      _reloadFromStore(syncControllers: true);
      showToast('已删除', type: ToastType.success);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      showToast('删除失败', type: ToastType.error);
    }
  }

  Future<void> _fetchModels() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      showToast('请先选择供应商', type: ToastType.warning);
      return;
    }
    // Prefer form values so user can pull before/after save.
    final baseRaw = _baseUrlController.text.trim().isNotEmpty
        ? _baseUrlController.text.trim()
        : supplier.baseUrl.trim();
    final key = _apiKeyController.text.trim().isNotEmpty
        ? _apiKeyController.text.trim()
        : supplier.apiKey.trim();
    final normalized =
        ModelProviderConfigService.normalizeApiBase(baseRaw) ?? baseRaw;
    if (normalized.isEmpty || key.isEmpty) {
      showToast('请先填写 API Base 与 Key', type: ToastType.warning);
      return;
    }

    // Persist form fields first so library stays consistent.
    if (normalized != supplier.baseUrl ||
        key != supplier.apiKey ||
        _memoController.text.trim() != supplier.memoName) {
      await _saveSelected();
      if (!mounted) {
        return;
      }
    }

    final host = Uri.tryParse(normalized)?.host ?? '';
    setState(() {
      _isFetchingModels = true;
      _statusMessage = null;
    });
    try {
      final CodexHttpModelsResult result;
      if (widget.listModelsOverride != null) {
        result = await widget.listModelsOverride!(
          baseUrl: normalized,
          apiKey: key,
        );
      } else {
        result = await CodexAppServerService.listModelsFromProviderHttp(
          baseUrl: normalized,
          apiKey: key,
        );
      }
      // Never log key; only host + count.
      debugPrint(
        'CodexSupplierSetting: fetched ${result.modelIds.length} models host=$host',
      );
      await CodexSupplierStore.mergeFetchedModels(
        supplierId: supplier.id,
        remoteModelIds: result.modelIds,
        defaultEnableNew: true,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      setState(() {
        _isFetchingModels = false;
        _statusIsError = false;
        _statusMessage =
            '已拉取 ${result.modelIds.length} 个模型（新 id 默认启用）';
      });
      showToast(
        '已拉取 ${result.modelIds.length} 个模型',
        type: ToastType.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _friendlyFetchError(error, host: host);
      setState(() {
        _isFetchingModels = false;
        _statusIsError = true;
        _statusMessage = message;
      });
      showToast(message, type: ToastType.error);
    }
  }

  String _friendlyFetchError(Object error, {required String host}) {
    final text = error.toString();
    // Strip accidental secrets if any intermediate layer echoed them.
    final sanitized = text
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]+'), 'sk-***')
        .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer ***');
    if (error is CodexHttpModelsException) {
      final code = error.statusCode;
      final epHost = host.isEmpty ? '' : ' · $host';
      if (code != null) {
        return '拉取模型失败 HTTP $code$epHost';
      }
      return '拉取模型失败$epHost';
    }
    if (sanitized.contains('FormatException')) {
      return '拉取模型失败：响应不是 OpenAI 兼容的 /models 格式'
          '${host.isEmpty ? '' : ' · $host'}';
    }
    if (sanitized.contains('TimeoutException') ||
        sanitized.toLowerCase().contains('timeout')) {
      return '拉取模型超时${host.isEmpty ? '' : ' · $host'}';
    }
    return '拉取模型失败${host.isEmpty ? '' : ' · $host'}';
  }

  Future<void> _addManualModel() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      showToast('请先选择供应商', type: ToastType.warning);
      return;
    }
    _manualModelController.text = '';
    final modelId = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('手填模型 id'),
          content: TextField(
            key: const Key('codex-supplier-manual-model-field'),
            controller: _manualModelController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '例如 gpt-4.1 或 o3',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_manualModelController.text.trim()),
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
    final id = modelId?.trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    try {
      await CodexSupplierStore.addManualModel(
        supplierId: supplier.id,
        modelId: id,
        enabled: true,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      showToast('已添加 $id', type: ToastType.success);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showToast('添加失败', type: ToastType.error);
    }
  }

  Future<void> _toggleModel(CodexSupplierModelEntry model, bool enabled) async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      return;
    }
    try {
      await CodexSupplierStore.setModelEnabled(
        supplierId: supplier.id,
        modelId: model.id,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showToast('更新失败', type: ToastType.error);
    }
  }

  Future<void> _selectVisible() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      return;
    }
    final ids = _visibleModels.map((item) => item.id);
    try {
      await CodexSupplierStore.setVisibleModelsEnabled(
        supplierId: supplier.id,
        visibleModelIds: ids,
        enabled: true,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      showToast('已全选当前可见', type: ToastType.info);
    } catch (_) {
      showToast('操作失败', type: ToastType.error);
    }
  }

  Future<void> _clearVisible() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      return;
    }
    final ids = _visibleModels.map((item) => item.id);
    try {
      await CodexSupplierStore.setVisibleModelsEnabled(
        supplierId: supplier.id,
        visibleModelIds: ids,
        enabled: false,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      showToast('已清空当前可见', type: ToastType.info);
    } catch (_) {
      showToast('操作失败', type: ToastType.error);
    }
  }

  Future<void> _invertVisible() async {
    final supplier = _selectedSupplier;
    if (supplier == null) {
      return;
    }
    final ids = _visibleModels.map((item) => item.id);
    try {
      await CodexSupplierStore.invertVisibleModels(
        supplierId: supplier.id,
        visibleModelIds: ids,
      );
      if (!mounted) {
        return;
      }
      _reloadFromStore(syncControllers: false);
      showToast('已反选当前可见', type: ToastType.info);
    } catch (_) {
      showToast('操作失败', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('codex-supplier-setting-page'),
      backgroundColor: _pageBackground,
      appBar: CommonAppBar(
        title: 'Codex 供应商',
        backgroundColor: _pageBackground,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _buildLockedBanner(),
                const SizedBox(height: 12),
                SettingsSectionTitle(
                  label: '我的供应商',
                  bottomPadding: 8,
                ),
                _buildSupplierListCard(),
                const SizedBox(height: 16),
                SettingsSectionTitle(
                  label: '连接信息',
                  bottomPadding: 8,
                ),
                _buildFormCard(),
                const SizedBox(height: 16),
                SettingsSectionTitle(
                  label: '模型库 · 勾选启用',
                  bottomPadding: 8,
                ),
                _buildModelsCard(),
              ],
            ),
    );
  }

  Widget _buildLockedBanner() {
    return Container(
      key: const Key('codex-supplier-wire-locked'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _chipBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '协议锁定 wire_api = responses',
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '用户只填备注（可选）· API Base · API Key。不提供 chat_completions / 协议选择。与 Agent 供应商库隔离。',
            style: TextStyle(color: _secondaryTextColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierListCard() {
    final suppliers = _library.suppliers;
    return Container(
      key: const Key('codex-supplier-list'),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    suppliers.isEmpty ? '还没有供应商' : '共 ${suppliers.length} 个',
                    style: TextStyle(color: _secondaryTextColor, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  key: const Key('codex-supplier-add-button'),
                  onPressed: _isSaving ? null : _createSupplier,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增'),
                ),
              ],
            ),
          ),
          if (suppliers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                '点「新增」创建 Codex 私有供应商。不会写入 Agent 库。',
                style: TextStyle(color: _secondaryTextColor, fontSize: 13),
              ),
            )
          else
            ...suppliers.map(_buildSupplierTile),
        ],
      ),
    );
  }

  Widget _buildSupplierTile(CodexSupplierRecord supplier) {
    final selected = supplier.id == _selectedSupplierId;
    final enabled = supplier.enabledModelIds.length;
    final host = Uri.tryParse(supplier.baseUrl)?.host ?? supplier.baseUrl;
    return Material(
      color: selected
          ? (_isDarkTheme
                ? context.omniPalette.surfaceSecondary
                : _accentColor.withValues(alpha: 0.06))
          : Colors.transparent,
      child: ListTile(
        key: Key('codex-supplier-item-${supplier.id}'),
        dense: true,
        selected: selected,
        onTap: () => _selectSupplier(supplier.id),
        title: Text(
          supplier.displayName,
          style: TextStyle(
            color: _primaryTextColor,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${host.isEmpty ? '未配置 Base' : host} · 启用 $enabled',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _secondaryTextColor, fontSize: 12),
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: _accentColor, size: 20)
            : Icon(Icons.chevron_right, color: _secondaryTextColor, size: 20),
      ),
    );
  }

  Widget _buildFormCard() {
    final hasSelection = _selectedSupplier != null;
    return Container(
      key: const Key('codex-supplier-form'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasSelection)
            Text(
              '请先新增或选择一个供应商。',
              style: TextStyle(color: _secondaryTextColor, fontSize: 13),
            )
          else ...[
            _buildTextField(
              key: const Key('codex-supplier-memo-field'),
              controller: _memoController,
              label: '备注名（可选，仅展示）',
              hint: '例如 公司中转 / 工作号',
              enabled: !_isSaving,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              key: const Key('codex-supplier-base-url-field'),
              controller: _baseUrlController,
              label: 'API Base URL',
              hint: 'https://api.example.com/v1',
              keyboardType: TextInputType.url,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              key: const Key('codex-supplier-api-key-field'),
              controller: _apiKeyController,
              label: 'API Key',
              hint: 'sk-...',
              obscureText: _obscureApiKey,
              enabled: !_isSaving,
              suffix: IconButton(
                key: const Key('codex-supplier-api-key-visibility'),
                onPressed: () {
                  setState(() {
                    _obscureApiKey = !_obscureApiKey;
                  });
                },
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: _secondaryTextColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'wire_api = responses（系统固定 · 不可改）',
                style: TextStyle(color: _secondaryTextColor, fontSize: 12),
              ),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                key: const Key('codex-supplier-status'),
                style: TextStyle(
                  color: _statusIsError ? AppColors.alertRed : _successColor,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('codex-supplier-delete-button'),
                    onPressed: _isSaving ? null : _deleteSelected,
                    child: const Text('删除'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('codex-supplier-save-button'),
                    onPressed: _isSaving ? null : _saveSelected,
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelsCard() {
    final hasSelection = _selectedSupplier != null;
    final visible = _visibleModels;
    return Container(
      key: const Key('codex-supplier-models'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            hasSelection
                ? '当前：${_selectedSupplier!.displayName}'
                : '选择供应商后可拉取 / 勾选模型',
            style: TextStyle(color: _secondaryTextColor, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('codex-supplier-fetch-models'),
                  onPressed: (!hasSelection || _isFetchingModels || _isSaving)
                      ? null
                      : _fetchModels,
                  child: _isFetchingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('拉取 /models'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('codex-supplier-manual-model'),
                  onPressed: (!hasSelection || _isSaving) ? null : _addManualModel,
                  child: const Text('手填模型 id'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('codex-supplier-model-search'),
            controller: _searchController,
            enabled: hasSelection,
            decoration: InputDecoration(
              hintText: '搜索模型（支持几百条过滤）',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('codex-supplier-select-visible'),
                onPressed: (!hasSelection || visible.isEmpty)
                    ? null
                    : _selectVisible,
                child: const Text('全选可见'),
              ),
              OutlinedButton(
                key: const Key('codex-supplier-clear-visible'),
                onPressed: (!hasSelection || visible.isEmpty)
                    ? null
                    : _clearVisible,
                child: const Text('清空可见'),
              ),
              OutlinedButton(
                key: const Key('codex-supplier-invert-visible'),
                onPressed: (!hasSelection || visible.isEmpty)
                    ? null
                    : _invertVisible,
                child: const Text('反选可见'),
              ),
              Text(
                key: const Key('codex-supplier-model-stat'),
                '启用 $_enabledCount / 可见 $_visibleCount / 总数 $_totalCount',
                style: TextStyle(color: _secondaryTextColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasSelection)
            Text(
              '先新增供应商并填写 API。',
              style: TextStyle(color: _secondaryTextColor, fontSize: 13),
            )
          else if (_totalCount == 0)
            Text(
              key: const Key('codex-supplier-model-empty'),
              '还没有模型。点「拉取 /models」或「手填模型 id」。\n拉取后默认全选。',
              style: TextStyle(color: _secondaryTextColor, fontSize: 13),
            )
          else if (visible.isEmpty)
            Text(
              '没有匹配「$_searchQuery」的模型',
              style: TextStyle(color: _secondaryTextColor, fontSize: 13),
            )
          else
            ...visible.map((model) {
              return CheckboxListTile(
                key: Key('codex-supplier-model-${model.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: model.enabled,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  unawaited(_toggleModel(model, value));
                },
                title: Text(
                  model.label,
                  style: TextStyle(color: _primaryTextColor, fontSize: 13),
                ),
                subtitle: model.displayName.trim().isEmpty ||
                        model.displayName == model.id
                    ? null
                    : Text(
                        model.id,
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 11,
                        ),
                      ),
              );
            }),
          const SizedBox(height: 6),
          Text(
            '规则：远端列表默认全选；搜索后可对可见集批量勾选。设置页当前模型只显示已启用项。',
            style: TextStyle(color: _secondaryTextColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
    bool enabled = true,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: _secondaryTextColor, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          key: key,
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: (_) {
            if (_syncingControllers) {
              return;
            }
          },
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            suffixIcon: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
