import 'package:flutter/material.dart';
import 'package:ui/services/model_provider_config_service.dart';

class CodexProviderSelector extends StatelessWidget {
  const CodexProviderSelector({
    super.key,
    required this.providers,
    required this.activeProviderId,
    required this.models,
    required this.activeModelId,
    required this.busy,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onManageProviders,
  });

  final List<ModelProviderProfileSummary> providers;
  final String activeProviderId;
  final List<ProviderModelOption> models;
  final String activeModelId;
  final bool busy;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final VoidCallback onManageProviders;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final providerIds = providers.map((item) => item.id).toSet();
    final modelIds = models.map((item) => item.id).toSet();
    final providerValue = providerIds.contains(activeProviderId)
        ? activeProviderId
        : null;
    final modelValue = modelIds.contains(activeModelId)
        ? activeModelId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                english ? 'Local Codex supplier' : '本地 Codex 供应商',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'PingFang SC',
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('codex-provider-manage-button'),
              onPressed: busy ? null : onManageProviders,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(english ? 'Manage' : '管理供应商'),
            ),
          ],
        ),
        Text(
          english
              ? 'Names are memos only. Codex always uses the internal omnimind profile.'
              : '名称仅用于备注；Codex 内部始终使用 omnimind profile。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        KeyedSubtree(
          key: ValueKey<String>(
            'codex-provider-$activeProviderId-${busy ? 'busy' : 'idle'}',
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('codex-provider-selector'),
            value: providerValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Supplier' : '供应商',
              isDense: true,
            ),
            items: providers.map((provider) {
              final compatibility =
                  ModelProviderConfigService.codexCompatibility(provider);
              return DropdownMenuItem<String>(
                value: provider.id,
                enabled: compatibility.isSupported && !busy,
                child: Text(
                  compatibility.isSupported
                      ? provider.name
                      : '${provider.name} — ${compatibility.reason}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null && value != activeProviderId) {
                      onProviderChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>(
            'codex-model-$activeProviderId-$activeModelId-'
            '${busy ? 'busy' : 'idle'}',
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('codex-provider-model-selector'),
            value: modelValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Provider model' : '供应商模型',
              helperText: models.isEmpty
                  ? (english
                        ? 'Add or fetch models in provider management first.'
                        : '请先在供应商管理中手动添加或拉取模型。')
                  : null,
              isDense: true,
            ),
            items: models
                .map(
                  (model) => DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(
                      model.displayName.isEmpty
                          ? model.id
                          : model.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null && value != activeModelId) {
                      onModelChanged(value);
                    }
                  },
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(english ? 'Switching supplier...' : '正在切换供应商...'),
            ],
          ),
        ],
      ],
    );
  }
}
