import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/codex/codex_bridge_qr_scanner_page.dart';
import 'package:ui/features/home/pages/codex/codex_remote_directory_picker.dart';
import 'package:ui/features/home/pages/codex/widgets/codex_provider_selector.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/codex_app_server_service.dart';
import 'package:ui/services/model_provider_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/settings_section_title.dart';

class CodexSettingPage extends StatefulWidget {
  const CodexSettingPage({super.key});

  @override
  State<CodexSettingPage> createState() => _CodexSettingPageState();
}

class _CodexSettingPageState extends State<CodexSettingPage> {
  static const String _defaultCodexHome = '/root/.codex';
  static const Duration _autoSaveDelay = Duration(milliseconds: 700);

  late final TextEditingController _bridgeUrlController;
  late final TextEditingController _bridgeTokenController;
  late final TextEditingController _bridgeCwdController;

  Timer? _saveDebounce;
  CodexLocalConfig? _localConfig;
  CodexProviderState _providerState = const CodexProviderState();
  List<ModelProviderProfileSummary> _providers = const [];
  List<ProviderModelOption> _providerModels = const [];
  int _providerLoadGeneration = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTestingBridge = false;
  bool _isSyncing = false;
  bool _obscureBridgeToken = true;
  bool _remoteEnabled = false;
  String _codexHome = _defaultCodexHome;
  String _runtime = 'local';
  String? _error;
  String? _status;
  String? _lastSavedSignature;

  bool get _isEnglish => Localizations.localeOf(context).languageCode == 'en';
  bool get _isDarkTheme => context.isDarkTheme;
  Color get _pageBackground =>
      _isDarkTheme ? context.omniPalette.pageBackground : AppColors.background;
  Color get _cardColor =>
      _isDarkTheme ? context.omniPalette.surfacePrimary : Colors.white;
  Color get _primaryTextColor =>
      _isDarkTheme ? context.omniPalette.textPrimary : AppColors.text;
  Color get _secondaryTextColor =>
      _isDarkTheme ? context.omniPalette.textSecondary : AppColors.text70;
  Color get _tertiaryTextColor =>
      _isDarkTheme ? context.omniPalette.textTertiary : AppColors.text50;
  Color get _mutedSurfaceColor => _isDarkTheme
      ? context.omniPalette.surfaceSecondary.withValues(alpha: 0.72)
      : const Color(0xFFF8FAFC);
  InputBorder get _borderlessInputBorder => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide.none,
  );

  String _localeText({required String zh, required String en}) {
    return _isEnglish ? en : zh;
  }

  @override
  void initState() {
    super.initState();
    _bridgeUrlController = TextEditingController();
    _bridgeTokenController = TextEditingController();
    _bridgeCwdController = TextEditingController();
    for (final controller in [
      _bridgeUrlController,
      _bridgeTokenController,
      _bridgeCwdController,
    ]) {
      controller.addListener(_handleEdited);
    }
    unawaited(_loadConfig());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    for (final controller in [
      _bridgeUrlController,
      _bridgeTokenController,
      _bridgeCwdController,
    ]) {
      controller.removeListener(_handleEdited);
      controller.dispose();
    }
    super.dispose();
  }

  void _setControllerText(TextEditingController controller, String text) {
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _syncControllers(CodexLocalConfig config) {
    _isSyncing = true;
    try {
      _setControllerText(_bridgeUrlController, config.remoteBridgeUrl);
      _setControllerText(_bridgeTokenController, config.remoteBridgeToken);
      _setControllerText(_bridgeCwdController, config.remoteCwd);
      _remoteEnabled = config.remoteEnabled;
    } finally {
      _isSyncing = false;
    }
  }

  String _signature({
    required String remoteBridgeUrl,
    required String remoteBridgeToken,
    required String remoteCwd,
    required bool remoteEnabled,
  }) {
    return [
      remoteEnabled ? 'remote' : 'local',
      remoteBridgeUrl.trim(),
      remoteBridgeToken.trim(),
      remoteCwd.trim(),
    ].join('\n');
  }

  String _currentSignature() {
    return _signature(
      remoteBridgeUrl: _bridgeUrlController.text,
      remoteBridgeToken: _bridgeTokenController.text,
      remoteCwd: _bridgeCwdController.text,
      remoteEnabled: _remoteEnabled,
    );
  }

  bool get _hasAnyRemoteInput =>
      _bridgeUrlController.text.trim().isNotEmpty ||
      _bridgeTokenController.text.trim().isNotEmpty ||
      _bridgeCwdController.text.trim().isNotEmpty;

  bool get _hasCompleteLocalInput {
    final config = _localConfig;
    return config != null &&
        config.baseUrl.trim().isNotEmpty &&
        config.model.trim().isNotEmpty &&
        config.apiKey.trim().isNotEmpty;
  }

  bool get _hasCompleteRemoteInput =>
      _bridgeUrlController.text.trim().isNotEmpty &&
      _bridgeCwdController.text.trim().isNotEmpty;

  bool get _isChangingRemoteEnabled => _remoteEnabled != (_runtime == 'remote');

  bool get _hasCompleteInput {
    if (_remoteEnabled) return _hasCompleteRemoteInput;
    if (_isChangingRemoteEnabled) return true;
    return _hasCompleteLocalInput;
  }

  bool get _isRemoteIncomplete => _remoteEnabled && !_hasCompleteRemoteInput;

  void _handleEdited() {
    if (_isSyncing || !mounted) return;
    _saveDebounce?.cancel();
    final signature = _currentSignature();
    final anyInput = _hasAnyRemoteInput || _remoteEnabled;
    setState(() {
      _error = null;
      if (_isRemoteIncomplete) {
        _status = _localeText(
          zh: '远程 Bridge URL 与远程工作目录填写完整后将自动保存。',
          en: 'Remote Bridge URL and remote cwd are required to autosave.',
        );
      } else if (!anyInput) {
        _status = null;
      } else if (!_hasCompleteInput) {
        _status = _localeText(
          zh: _remoteEnabled ? '填写完整后将自动保存。' : '本地配置填写完整后将自动保存。',
          en: _remoteEnabled
              ? 'Complete all fields to autosave.'
              : 'Complete the local config to autosave.',
        );
      } else if (signature == _lastSavedSignature) {
        _status = _localeText(zh: '已自动保存。', en: 'Autosaved.');
      } else {
        _status = _localeText(zh: '即将自动保存...', en: 'Autosave pending...');
      }
    });
    if (_hasCompleteInput && signature != _lastSavedSignature) {
      _scheduleAutoSave();
    }
  }

  void _setRemoteEnabled(bool value) {
    if (_remoteEnabled == value) return;
    setState(() {
      _remoteEnabled = value;
      _error = null;
      _status = value
          ? _localeText(
              zh: '远程模式已开启，填写 Bridge URL 与远程工作目录后将自动保存。',
              en: 'Remote mode is enabled. Fill Bridge URL and remote cwd to autosave.',
            )
          : _localeText(
              zh: '远程模式已关闭，将切换为本地 Alpine Codex。',
              en: 'Remote mode is disabled. Codex will use local Alpine.',
            );
    });
    if (_hasCompleteInput && _currentSignature() != _lastSavedSignature) {
      _scheduleAutoSave(delay: const Duration(milliseconds: 300));
    }
  }

  void _scheduleAutoSave({Duration delay = _autoSaveDelay}) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(delay, () => unawaited(_saveConfig()));
  }

  Future<void> _loadConfig() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final config = await CodexAppServerService.readLocalConfig();
      final payload = await ModelProviderConfigService.listProfiles();
      var state = ModelProviderConfigService.readCodexProviderState();
      var providers = payload.profiles;
      ModelProviderProfileSummary? active;
      final nativeModel = config.model.trim();
      bool matchesNativeEndpoint(ModelProviderProfileSummary provider) {
        return config.modelProvider.trim() == 'omnimind' &&
            ModelProviderConfigService.normalizeApiBase(provider.baseUrl) ==
                ModelProviderConfigService.normalizeApiBase(config.baseUrl) &&
            provider.apiKey.trim() == config.apiKey.trim() &&
            ModelProviderConfigService.codexCompatibility(provider)
                .isSupported;
      }

      ModelProviderProfileSummary? rememberedProvider;
      for (final provider in providers) {
        if (provider.id == state.activeProviderId &&
            ModelProviderConfigService.codexCompatibility(provider)
                .isSupported) {
          rememberedProvider = provider;
          break;
        }
      }
      final endpointCandidates = providers
          .where(matchesNativeEndpoint)
          .toList(growable: false);
      final candidateModels = <String, List<ProviderModelOption>>{};
      await Future.wait(
        endpointCandidates.map((provider) async {
          candidateModels[provider.id] =
              await ModelProviderConfigService.getStoredModelOptionsForProfile(
            provider.id,
            profile: provider,
          );
        }),
      );
      final exactCandidates = endpointCandidates.where((provider) {
        final models =
            candidateModels[provider.id] ?? const <ProviderModelOption>[];
        final rememberedModel = state.currentModels[provider.id] ?? '';
        return models.any((item) => item.id == nativeModel) ||
            (provider.id == state.activeProviderId &&
                rememberedModel == nativeModel);
      }).toList(growable: false);
      if (rememberedProvider != null &&
          exactCandidates.any(
            (provider) => provider.id == rememberedProvider!.id,
          )) {
        active = rememberedProvider;
      } else if (exactCandidates.length == 1) {
        active = exactCandidates.single;
      } else if (exactCandidates.isEmpty &&
          endpointCandidates.length == 1) {
        // A unique endpoint/key identity is safe to attach to its existing
        // stable record; ambiguity must never fall back to list order.
        active = endpointCandidates.single;
      }
      if (active == null &&
          state.activeProviderId.isEmpty &&
          endpointCandidates.isEmpty &&
          config.baseUrl.trim().isNotEmpty &&
          config.apiKey.trim().isNotEmpty &&
          nativeModel.isNotEmpty) {
        active = await ModelProviderConfigService.saveProfile(
          name: 'Codex supplier',
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          wireApi: 'responses',
        );
        providers = <ModelProviderProfileSummary>[...providers, active];
      }
      var models = const <ProviderModelOption>[];
      if (active != null) {
        models =
            candidateModels[active.id] ??
            await ModelProviderConfigService.getStoredModelOptionsForProfile(
              active.id,
              profile: active,
            );
        final sameLegacyProvider =
            matchesNativeEndpoint(active);
        if (sameLegacyProvider &&
            nativeModel.isNotEmpty &&
            !models.any((item) => item.id == nativeModel)) {
          final manual = await ModelProviderConfigService.getManualModelIds(
            profileId: active.id,
          );
          await ModelProviderConfigService.saveManualModelIds(
            profileId: active.id,
            ids: <String>[...manual, nativeModel],
          );
          models = <ProviderModelOption>[
            ...models,
            ProviderModelOption(
              id: nativeModel,
              displayName: nativeModel,
              ownedBy: 'manual',
            ),
          ];
        }
        final remembered = state.currentModels[active.id] ?? '';
        final selectedModel = models.any((item) => item.id == nativeModel)
            ? nativeModel
            : models.any((item) => item.id == remembered)
                ? remembered
                : (models.isEmpty ? '' : models.first.id);
        final nextState = selectedModel.isEmpty
            ? state
            : state.selecting(
                providerId: active.id,
                modelId: selectedModel,
              );
        final nativeSelectionMatches =
            matchesNativeEndpoint(active) && nativeModel == selectedModel;
        if (selectedModel.isNotEmpty &&
            nativeSelectionMatches &&
            (nextState.activeProviderId != state.activeProviderId ||
                !mapEquals(nextState.currentModels, state.currentModels))) {
          await ModelProviderConfigService.commitCodexProviderState(nextState);
          state = nextState;
        }
      } else if (state.activeProviderId.isNotEmpty) {
        // Keep per-provider remembered models, but do not render a stale
        // supplier id as active when Native identity cannot select it exactly.
        state = CodexProviderState(currentModels: state.currentModels);
      }
      if (!mounted) return;
      _syncControllers(config);
      setState(() {
        _localConfig = config;
        _providers = providers;
        _providerState = state;
        _providerModels = models;
        _codexHome = config.codexHome ?? _defaultCodexHome;
        _runtime = config.runtime ?? 'local';
        _isLoading = false;
        _error = active == null &&
                config.baseUrl.trim().isNotEmpty &&
                nativeModel.isNotEmpty
            ? _localeText(
                zh: '本地 Codex 配置无法唯一匹配供应商记录，请重新选择供应商。',
                en: 'Local Codex config does not uniquely match a supplier record. Select a supplier again.',
              )
            : null;
        _status = null;
        _lastSavedSignature = _currentSignature();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _localeText(
          zh: 'Codex 配置读取失败：$error',
          en: 'Failed to read Codex config: $error',
        );
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_isSaving) return;
    if (_isRemoteIncomplete || !_hasCompleteInput) {
      if (!mounted) return;
      setState(() {
        _status = _isRemoteIncomplete
            ? _localeText(
                zh: '远程 Bridge URL 与远程工作目录填写完整后将自动保存。',
                en: 'Remote Bridge URL and remote cwd are required to autosave.',
              )
            : _localeText(
                zh: _remoteEnabled ? '填写完整后将自动保存。' : '本地配置填写完整后将自动保存。',
                en: _remoteEnabled
                    ? 'Complete all fields to autosave.'
                    : 'Complete the local config to autosave.',
              );
      });
      return;
    }

    final savingSignature = _currentSignature();
    if (savingSignature == _lastSavedSignature) {
      if (mounted) {
        setState(() => _status = _localeText(zh: '已自动保存。', en: 'Autosaved.'));
      }
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
      _status = _localeText(zh: '正在自动保存...', en: 'Autosaving...');
    });
    try {
      final current = _localConfig;
      if (current == null) {
        throw StateError('Codex local config is unavailable');
      }
      final saved = await CodexAppServerService.writeLocalConfig(
        baseUrl: current.baseUrl,
        model: current.model,
        apiKey: current.apiKey,
        serviceTier: current.serviceTier,
        fastMode: current.fastMode,
        autoCompaction: current.autoCompaction,
        contextTokenThreshold: current.contextTokenThreshold,
        modelReasoningEffort: current.modelReasoningEffort,
        remoteEnabled: _remoteEnabled,
        remoteBridgeUrl: _bridgeUrlController.text.trim(),
        remoteBridgeToken: _bridgeTokenController.text.trim(),
        remoteCwd: _bridgeCwdController.text.trim(),
      );
      if (!mounted) return;
      final savedSignature = _signature(
        remoteBridgeUrl: saved.remoteBridgeUrl,
        remoteBridgeToken: saved.remoteBridgeToken,
        remoteCwd: saved.remoteCwd,
        remoteEnabled: saved.remoteEnabled,
      );
      if (_currentSignature() == savingSignature) {
        _syncControllers(saved);
      }
      setState(() {
        _localConfig = saved;
        _codexHome = saved.codexHome ?? _defaultCodexHome;
        _runtime = saved.runtime ?? 'local';
        _lastSavedSignature = savedSignature;
        _error = null;
        _status = _currentSignature() == savedSignature
            ? _localeText(
                zh: saved.remoteEnabled
                    ? '已自动保存，Codex 模式将使用远程 PC Bridge。'
                    : '已自动保存，将使用本地 Alpine Codex。',
                en: saved.remoteEnabled
                    ? 'Autosaved. Codex mode will use the remote PC Bridge.'
                    : 'Autosaved. Codex mode will use local Alpine Codex.',
              )
            : _localeText(zh: '即将自动保存...', en: 'Autosave pending...');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _localeText(
          zh: 'Codex 配置保存失败：$error',
          en: 'Failed to save Codex config: $error',
        );
        _status = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        if (_hasCompleteInput && _currentSignature() != savingSignature) {
          _scheduleAutoSave(delay: const Duration(milliseconds: 300));
        }
      }
    }
  }

  Future<void> _switchProvider(String providerId, {String? modelId}) async {
    if (_isSaving) return;
    _saveDebounce?.cancel();
    final previousConfig = _localConfig;
    if (previousConfig == null) return;
    ModelProviderProfileSummary? provider;
    for (final item in _providers) {
      if (item.id == providerId) {
        provider = item;
        break;
      }
    }
    if (provider == null) return;
    final generation = ++_providerLoadGeneration;
    setState(() {
      _isSaving = true;
      _error = null;
      _status = _localeText(zh: '正在切换供应商...', en: 'Switching supplier...');
    });
    try {
      final models =
          providerId == _providerState.activeProviderId && modelId != null
              ? _providerModels
              : await ModelProviderConfigService.getStoredModelOptionsForProfile(
                  providerId,
                  profile: provider,
                );
      if (!mounted || generation != _providerLoadGeneration) return;
      final remembered = _providerState.currentModels[providerId] ?? '';
      final targetModel = modelId?.trim().isNotEmpty == true
          ? modelId!.trim()
          : models.any((item) => item.id == remembered)
              ? remembered
              : (models.isEmpty ? '' : models.first.id);
      final saved = await CodexAppServerService.switchLocalProvider(
        provider: provider,
        model: targetModel,
        availableModelIds: models.map((item) => item.id).toList(),
        previousConfig: previousConfig,
        previousState: _providerState,
      );
      if (!mounted || generation != _providerLoadGeneration) return;
      setState(() {
        _localConfig = saved;
        _providerModels = models;
        _providerState = _providerState.selecting(
          providerId: providerId,
          modelId: targetModel,
        );
        _error = null;
        _status = _localeText(zh: '供应商已切换。', en: 'Supplier switched.');
      });
    } catch (error) {
      if (!mounted || generation != _providerLoadGeneration) return;
      setState(() {
        _error = _localeText(
          zh: '供应商切换失败：$error',
          en: 'Failed to switch supplier: $error',
        );
        _status = null;
      });
    } finally {
      if (mounted && generation == _providerLoadGeneration) {
        setState(() => _isSaving = false);
        if (_hasCompleteInput &&
            _currentSignature() != _lastSavedSignature) {
          _scheduleAutoSave(delay: const Duration(milliseconds: 300));
        }
      }
    }
  }

  Future<void> _manageProviders() async {
    final previousConfig = _localConfig;
    final previousState = _providerState;
    await GoRouterManager.pushForResult<Object?>('/home/model_provider_setting');
    if (!mounted || previousConfig == null) {
      return;
    }
    try {
      final payload = await ModelProviderConfigService.listProfiles();
      if (!mounted) return;
      final providerId = previousState.activeProviderId;
      final stillExists = payload.profiles.any(
        (provider) => provider.id == providerId,
      );
      setState(() {
        _providers = payload.profiles;
        _localConfig = previousConfig;
        _providerState = previousState;
        if (!stillExists) {
          _providerModels = const [];
          _error = _localeText(
            zh: '当前供应商已被删除，请选择新的供应商。',
            en: 'The active supplier was deleted. Select another supplier.',
          );
          _status = null;
        }
      });
      if (stillExists) {
        // Reload the edited supplier's library, then commit selection only
        // through the Native-first switch transaction.
        await _switchProvider(providerId);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _localeText(
          zh: '供应商列表刷新失败：$error',
          en: 'Failed to refresh suppliers: $error',
        );
        _status = null;
      });
    }
  }

  Future<void> _testBridgeConnection() async {
    if (_isTestingBridge) return;
    final bridgeUrl = _bridgeUrlController.text.trim();
    final cwd = _bridgeCwdController.text.trim();
    if (bridgeUrl.isEmpty || cwd.isEmpty) {
      showToast(
        _localeText(
          zh: '测试连接需要填写 Bridge URL 与远程工作目录。',
          en: 'Bridge URL and remote cwd are required for the connection test.',
        ),
        type: ToastType.warning,
      );
      return;
    }
    setState(() {
      _isTestingBridge = true;
      _error = null;
    });
    showToast(
      _localeText(zh: '正在测试远程 PC Bridge...', en: 'Testing remote PC Bridge...'),
      type: ToastType.loading,
      duration: const Duration(milliseconds: 1200),
    );
    try {
      final result = await CodexAppServerService.testRemoteConfig(
        remoteBridgeUrl: bridgeUrl,
        remoteBridgeToken: _bridgeTokenController.text.trim(),
        remoteCwd: cwd,
      );
      if (!mounted) return;
      final ok = result['ok'] == true || result['ready'] == true;
      final version = result['version']?.toString().trim() ?? '';
      final resolvedCwd = result['cwd']?.toString().trim() ?? '';
      showToast(
        ok
            ? _localeText(
                zh: '远程 Bridge 可用${version.isEmpty ? '' : '：$version'}${resolvedCwd.isEmpty ? '' : '，目录：$resolvedCwd'}',
                en: 'Remote Bridge is ready${version.isEmpty ? '' : ': $version'}${resolvedCwd.isEmpty ? '' : ', cwd: $resolvedCwd'}',
              )
            : _localeText(
                zh: '远程 Bridge 测试失败：${result['error'] ?? 'unknown'}',
                en: 'Remote Bridge test failed: ${result['error'] ?? 'unknown'}',
              ),
        type: ok ? ToastType.success : ToastType.error,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        _localeText(
          zh: '远程 Bridge 测试失败：$error',
          en: 'Remote Bridge test failed: $error',
        ),
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isTestingBridge = false);
      }
    }
  }

  Future<void> _openRemoteDirectoryPicker() async {
    final bridgeUrl = _bridgeUrlController.text.trim();
    if (bridgeUrl.isEmpty) {
      showToast(
        _localeText(
          zh: '请先填写 Bridge URL。',
          en: 'Bridge URL is required first.',
        ),
        type: ToastType.warning,
      );
      return;
    }
    final selected = await showCodexRemoteDirectoryPicker(
      context: context,
      remoteBridgeUrl: bridgeUrl,
      remoteBridgeToken: _bridgeTokenController.text.trim(),
      initialPath: _bridgeCwdController.text.trim(),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    _setControllerText(_bridgeCwdController, selected.trim());
    _handleEdited();
  }

  Future<void> _openBridgeQrScanner() async {
    final result = await Navigator.of(context).push<CodexBridgeQrScanResult>(
      MaterialPageRoute(
        builder: (_) => const CodexBridgeQrScannerPage(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || result == null) return;
    _saveDebounce?.cancel();
    _isSyncing = true;
    try {
      _setControllerText(_bridgeUrlController, result.bridgeUrl.trim());
      _setControllerText(_bridgeTokenController, result.token.trim());
      _setControllerText(_bridgeCwdController, result.cwd.trim());
      setState(() {
        _remoteEnabled = true;
        _error = null;
        _status = _localeText(
          zh: '已识别 Bridge 二维码，配置即将自动保存。',
          en: 'Bridge QR code scanned. Autosave pending.',
        );
      });
    } finally {
      _isSyncing = false;
    }
    showToast(
      _localeText(zh: '已填入远程 Bridge 配置。', en: 'Remote Bridge config filled.'),
      type: ToastType.success,
    );
    _handleEdited();
  }

  Widget _buildTextField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      key: key,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      style: TextStyle(
        color: _primaryTextColor,
        fontSize: 13,
        fontFamily: 'PingFang SC',
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: _mutedSurfaceColor,
        border: _borderlessInputBorder,
        enabledBorder: _borderlessInputBorder,
        focusedBorder: _borderlessInputBorder,
        disabledBorder: _borderlessInputBorder,
        errorBorder: _borderlessInputBorder,
        focusedErrorBorder: _borderlessInputBorder,
        isDense: true,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildRemoteSwitch() {
    return _buildSimpleSwitch(
      value: _remoteEnabled,
      onChanged: _setRemoteEnabled,
    );
  }

  Widget _buildSimpleSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final palette = context.omniPalette;
    final enabled = !_isSaving;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: AbsorbPointer(
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: FlutterSwitch(
              width: 32,
              height: 18.67,
              toggleSize: 11.3,
              padding: 3,
              activeColor: palette.accentPrimary,
              inactiveColor: palette.borderStrong,
              borderRadius: 28.75,
              value: value,
              onToggle: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isDarkTheme
        ? context.omniPalette.borderSubtle
        : const Color(0x1A000000);
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: CommonAppBar(
        title: LegacyTextLocalizer.localize('Codex 配置'),
        primary: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            SettingsSectionTitle(
              label: _localeText(zh: 'Codex 配置', en: 'Codex Config'),
              subtitle: _localeText(
                zh: '用开关明确选择远程 PC Bridge 或本地 Alpine。',
                en: 'Use the switch to choose remote PC Bridge or local Alpine.',
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _runtime == 'remote'
                                  ? Icons.hub_rounded
                                  : Icons.terminal_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _localeText(
                                  zh: _runtime == 'remote'
                                      ? '当前运行时：远程 PC Bridge'
                                      : '当前运行时：本地 Alpine（配置目录：$_codexHome）',
                                  en: _runtime == 'remote'
                                      ? 'Runtime: Remote PC Bridge'
                                      : 'Runtime: Local Alpine (config: $_codexHome)',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _secondaryTextColor,
                                  fontSize: 12,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('codex-config-refresh-button'),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: _localeText(zh: '重新读取', en: 'Reload'),
                              onPressed: _isSaving
                                  ? null
                                  : () => unawaited(_loadConfig()),
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: 17,
                                color: _tertiaryTextColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _localeText(
                                  zh: '远程 PC Bridge',
                                  en: 'Remote PC Bridge',
                                ),
                                style: TextStyle(
                                  color: _primaryTextColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'PingFang SC',
                                ),
                              ),
                            ),
                            _buildRemoteSwitch(),
                          ],
                        ),
                        Text(
                          _remoteEnabled
                              ? _localeText(
                                  zh: '已启用：Codex 模式将连接远程 PC Bridge。',
                                  en: 'Enabled: Codex mode will connect to the remote PC Bridge.',
                                )
                              : _localeText(
                                  zh: '已关闭：Codex 模式使用本地 Alpine。',
                                  en: 'Disabled: Codex mode uses local Alpine.',
                                ),
                          style: TextStyle(
                            color: _secondaryTextColor,
                            fontSize: 12,
                            height: 1.35,
                            fontFamily: 'PingFang SC',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          key: const Key(
                            'codex-config-remote-bridge-url-field',
                          ),
                          controller: _bridgeUrlController,
                          label: _localeText(
                            zh: 'Bridge URL',
                            en: 'Bridge URL',
                          ),
                          hint: 'ws://192.168.1.10:17321/codex',
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          key: const Key('codex-config-remote-cwd-field'),
                          controller: _bridgeCwdController,
                          label: _localeText(zh: '远程工作目录', en: 'Remote cwd'),
                          hint: '/Users/name/code/project',
                          suffixIcon: IconButton(
                            tooltip: _localeText(
                              zh: '选择目录',
                              en: 'Choose directory',
                            ),
                            onPressed: _openRemoteDirectoryPicker,
                            icon: const Icon(
                              Icons.folder_open_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          key: const Key('codex-config-remote-token-field'),
                          controller: _bridgeTokenController,
                          label: _localeText(
                            zh: 'Bridge Token（可选）',
                            en: 'Bridge Token (optional)',
                          ),
                          hint: 'OMNIBOT_BRIDGE_TOKEN',
                          obscureText: _obscureBridgeToken,
                          suffixIcon: IconButton(
                            tooltip: _obscureBridgeToken
                                ? _localeText(zh: '显示 Token', en: 'Show token')
                                : _localeText(zh: '隐藏 Token', en: 'Hide token'),
                            onPressed: () {
                              setState(() {
                                _obscureBridgeToken = !_obscureBridgeToken;
                              });
                            },
                            icon: Icon(
                              _obscureBridgeToken
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: const Key(
                                'codex-config-scan-bridge-qr-button',
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () => unawaited(_openBridgeQrScanner()),
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 17,
                              ),
                              label: Text(
                                _localeText(zh: '扫码连接', en: 'Scan QR'),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isTestingBridge
                                  ? null
                                  : () => unawaited(_testBridgeConnection()),
                              icon: _isTestingBridge
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.wifi_tethering_rounded,
                                      size: 17,
                                    ),
                              label: Text(
                                _isTestingBridge
                                    ? _localeText(
                                        zh: '测试中...',
                                        en: 'Testing...',
                                      )
                                    : _localeText(
                                        zh: '测试 Bridge 连接',
                                        en: 'Test Bridge',
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Divider(height: 1, color: borderColor),
                        const SizedBox(height: 12),
                        CodexProviderSelector(
                          providers: _providers,
                          activeProviderId: _providerState.activeProviderId,
                          models: _providerModels,
                          activeModelId:
                              _providerState.currentModels[
                                  _providerState.activeProviderId] ??
                              '',
                          busy: _isSaving,
                          onProviderChanged: (id) =>
                              unawaited(_switchProvider(id)),
                          onModelChanged: (id) => unawaited(
                            _switchProvider(
                              _providerState.activeProviderId,
                              modelId: id,
                            ),
                          ),
                          onManageProviders: () =>
                              unawaited(_manageProviders()),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _mutedSurfaceColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.restart_alt_rounded,
                                size: 17,
                                color: _tertiaryTextColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _localeText(
                                    zh: '远程开关关闭时使用所选供应商；供应商名称仅作备注，Codex 内部 profile 固定为 omnimind。',
                                    en: 'When remote mode is off, Codex uses the selected supplier. Its name is only a memo; the internal profile stays omnimind.',
                                  ),
                                  style: TextStyle(
                                    color: _secondaryTextColor,
                                    fontSize: 12,
                                    height: 1.45,
                                    fontFamily: 'PingFang SC',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                              height: 1.45,
                              fontFamily: 'PingFang SC',
                            ),
                          ),
                        ],
                        if (_status != null || _isSaving) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (_isSaving) ...[
                                const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else ...[
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 15,
                                  color: _tertiaryTextColor,
                                ),
                                const SizedBox(width: 7),
                              ],
                              Expanded(
                                child: Text(
                                  _status ??
                                      _localeText(
                                        zh: '正在自动保存...',
                                        en: 'Autosaving...',
                                      ),
                                  style: TextStyle(
                                    color: _secondaryTextColor,
                                    fontSize: 12,
                                    height: 1.45,
                                    fontFamily: 'PingFang SC',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
