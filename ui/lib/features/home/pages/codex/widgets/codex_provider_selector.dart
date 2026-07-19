import 'package:flutter/material.dart';
import 'package:ui/services/codex_supplier_store.dart';

class CodexProviderSelector extends StatelessWidget {
  const CodexProviderSelector({
    super.key,
    required this.suppliers,
    required this.activeSupplierId,
    required this.enabledModels,
    required this.activeModelId,
    required this.activeEffort,
    required this.busy,
    required this.onSupplierChanged,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onManageSuppliers,
  });

  final List<CodexSupplierRecord> suppliers;
  final String activeSupplierId;
  final List<CodexSupplierModelEntry> enabledModels;
  final String activeModelId;
  final String activeEffort;
  final bool busy;
  final ValueChanged<String> onSupplierChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onEffortChanged;
  final VoidCallback onManageSuppliers;

  static const List<String> _effortOptions = kCodexDefaultEfforts;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    final supplierIds = suppliers.map((item) => item.id).toSet();
    final modelIds = enabledModels.map((item) => item.id).toSet();
    final supplierValue =
        supplierIds.contains(activeSupplierId) ? activeSupplierId : null;
    final modelValue =
        modelIds.contains(activeModelId) ? activeModelId : null;
    final effortNorm = activeEffort.trim().toLowerCase();
    final effortValue =
        _effortOptions.contains(effortNorm) ? effortNorm : null;
    final hasEnabledModels = enabledModels.isNotEmpty;

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
              onPressed: busy ? null : onManageSuppliers,
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
            'codex-supplier-$activeSupplierId-${busy ? 'busy' : 'idle'}',
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('codex-provider-selector'),
            value: supplierValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Supplier' : '供应商',
              isDense: true,
            ),
            items: suppliers
                .map(
                  (supplier) => DropdownMenuItem<String>(
                    value: supplier.id,
                    enabled: !busy,
                    child: Text(
                      supplier.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null && value != activeSupplierId) {
                      onSupplierChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>(
            'codex-model-$activeSupplierId-$activeModelId-'
            '${busy ? 'busy' : 'idle'}',
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('codex-provider-model-selector'),
            value: modelValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Enabled model' : '已启用模型',
              helperText: hasEnabledModels
                  ? null
                  : (english
                        ? 'Enable at least one model in supplier management first.'
                        : '请先在供应商管理中启用至少一个模型。'),
              isDense: true,
            ),
            items: enabledModels
                .map(
                  (model) => DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(
                      model.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: busy || !hasEnabledModels
                ? null
                : (value) {
                    if (value != null && value != activeModelId) {
                      onModelChanged(value);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey<String>(
            'codex-effort-$activeSupplierId-$activeEffort-'
            '${busy ? 'busy' : 'idle'}',
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('codex-provider-effort-selector'),
            value: effortValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: english ? 'Reasoning effort' : '思考档',
              isDense: true,
            ),
            items: _effortOptions
                .map(
                  (effort) => DropdownMenuItem<String>(
                    value: effort,
                    child: Text(effort),
                  ),
                )
                .toList(),
            onChanged: busy || !hasEnabledModels
                ? null
                : (value) {
                    if (value != null && value != effortNorm) {
                      onEffortChanged(value);
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
