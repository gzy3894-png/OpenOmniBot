import 'package:ui/models/agent_skill_item.dart';

/// Slash / `@` skill panel helpers (M5).
///
/// Converts [AgentSkillItem] (or raw maps from the skill store) into the same
/// card schema used by Codex slash command panels so M3/M4/M6 can plug the
/// skills route without re-implementing field layout.
///
/// Card contract (handler-facing extras in **bold**):
/// - cardId, toolName, toolTitle, displayName
/// - toolType, toolTypeLabel, status, statusLabel, summary, progress
/// - controlType: `action`
/// - **skillId**, **skillName**, skillSource, skillEnabled, skillInstalled
/// - mentionToken (`@name`) for composer insertion
const String kCodexSkillPanelRouteName = 'skills';
const String kCodexSkillCardIdPrefix = 'slash-command-codex-skill-';
const String kCodexSkillEmptyCardId = 'slash-command-codex-skill-empty';
const String kCodexSkillLoadingCardId = 'slash-command-codex-skill-loading';
const String kCodexSkillErrorCardId = 'slash-command-codex-skill-error';

/// One-line empty copy for the skills sub-panel.
String codexSkillPanelEmptyMessage({bool isEnglish = false}) {
  return isEnglish ? 'No skills available' : '暂无可用技能';
}

/// Loading placeholder copy for the skills sub-panel.
String codexSkillPanelLoadingMessage({bool isEnglish = false}) {
  return isEnglish ? 'Loading skills…' : '正在加载技能…';
}

/// Error placeholder copy for the skills sub-panel.
String codexSkillPanelErrorMessage(
  String? detail, {
  bool isEnglish = false,
}) {
  final trimmed = detail?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  return isEnglish ? 'Failed to load skills' : '技能列表加载失败';
}

/// Builds slash-panel cards for a skill list.
///
/// - Prefers **enabled + installed** skills first, then name order.
/// - Optional [query] filters by name / description / id (case-insensitive).
/// - When the filtered list is empty, returns a single non-selectable
///   placeholder card with bilingual empty copy.
List<Map<String, dynamic>> buildCodexSkillPanelCards(
  Iterable<AgentSkillItem> skills, {
  String query = '',
  bool isEnglish = false,
  bool preferEnabled = true,
}) {
  final filtered = filterCodexSkillItems(
    skills,
    query: query,
    preferEnabled: preferEnabled,
  );
  if (filtered.isEmpty) {
    return <Map<String, dynamic>>[
      buildCodexSkillEmptyCard(isEnglish: isEnglish, query: query),
    ];
  }
  return filtered
      .map(
        (skill) => buildCodexSkillCard(
          skill,
          isEnglish: isEnglish,
        ),
      )
      .toList(growable: false);
}

/// Same as [buildCodexSkillPanelCards] but accepts raw store maps.
List<Map<String, dynamic>> buildCodexSkillPanelCardsFromMaps(
  Iterable<Map<String, dynamic>> rawSkills, {
  String query = '',
  bool isEnglish = false,
  bool preferEnabled = true,
}) {
  final items = rawSkills.map(AgentSkillItem.fromMap).toList(growable: false);
  return buildCodexSkillPanelCards(
    items,
    query: query,
    isEnglish: isEnglish,
    preferEnabled: preferEnabled,
  );
}

/// Loading / error / empty placeholder cards for the skills route.
List<Map<String, dynamic>> buildCodexSkillPanelStateCards({
  required bool isLoading,
  String? error,
  String query = '',
  bool isEnglish = false,
}) {
  if (isLoading) {
    return <Map<String, dynamic>>[
      buildCodexSkillLoadingCard(isEnglish: isEnglish),
    ];
  }
  if (error != null && error.trim().isNotEmpty) {
    return <Map<String, dynamic>>[
      buildCodexSkillErrorCard(error, isEnglish: isEnglish),
    ];
  }
  return <Map<String, dynamic>>[
    buildCodexSkillEmptyCard(isEnglish: isEnglish, query: query),
  ];
}

/// Filters and sorts skills for the panel.
///
/// Sort: installed first → enabled first (when [preferEnabled]) → name A–Z.
List<AgentSkillItem> filterCodexSkillItems(
  Iterable<AgentSkillItem> skills, {
  String query = '',
  bool preferEnabled = true,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final list = skills.where((skill) {
    if (normalizedQuery.isEmpty) return true;
    final name = skill.name.toLowerCase();
    final id = skill.id.toLowerCase();
    final description = skill.description.toLowerCase();
    return name.contains(normalizedQuery) ||
        id.contains(normalizedQuery) ||
        description.contains(normalizedQuery);
  }).toList();

  list.sort((a, b) {
    if (a.installed != b.installed) {
      return a.installed ? -1 : 1;
    }
    if (preferEnabled && a.enabled != b.enabled) {
      return a.enabled ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

/// Single skill → slash panel card map.
Map<String, dynamic> buildCodexSkillCard(
  AgentSkillItem skill, {
  bool isEnglish = false,
}) {
  final skillId = skill.id.trim().isNotEmpty ? skill.id.trim() : skill.name;
  final skillName = skill.name.trim().isNotEmpty ? skill.name.trim() : skillId;
  final mention = skillMentionToken(skillName);
  final summary = _oneLineSummary(skill.description);
  final status = skill.enabled ? 'success' : 'running';
  final statusLabel = _enabledStatusLabel(
    enabled: skill.enabled,
    installed: skill.installed,
    isEnglish: isEnglish,
  );
  final typeLabel = _sourceTypeLabel(skill, isEnglish: isEnglish);
  final progress = skill.enabled
      ? (isEnglish ? 'Tap to insert $mention' : '点选插入 $mention')
      : (isEnglish
            ? 'Disabled — enable in Skill Store'
            : '已禁用 — 请在技能商店启用');

  return <String, dynamic>{
    'cardId': '$kCodexSkillCardIdPrefix$skillId',
    'toolName': mention,
    'toolTitle': skillName,
    'displayName': skillName,
    'toolType': 'skill',
    'toolTypeLabel': typeLabel,
    'status': status,
    'statusLabel': statusLabel,
    'summary': summary.isEmpty
        ? (isEnglish ? 'No description' : '暂无简介')
        : summary,
    'progress': progress,
    'controlType': 'action',
    // Handler fields (M4): know which skill was selected.
    'skillId': skillId,
    'skillName': skillName,
    'skillSource': skill.source,
    'skillEnabled': skill.enabled,
    'skillInstalled': skill.installed,
    'mentionToken': mention,
    'nav': null,
  };
}

Map<String, dynamic> buildCodexSkillEmptyCard({
  bool isEnglish = false,
  String query = '',
}) {
  final hasQuery = query.trim().isNotEmpty;
  final summary = hasQuery
      ? (isEnglish
            ? 'No skills match “${query.trim()}”'
            : '没有匹配「${query.trim()}」的技能')
      : codexSkillPanelEmptyMessage(isEnglish: isEnglish);
  return <String, dynamic>{
    'cardId': kCodexSkillEmptyCardId,
    'toolName': '@skill',
    'toolTitle': isEnglish ? 'Skills' : '技能',
    'displayName': isEnglish ? 'Skills' : '技能',
    'toolType': 'skill',
    'toolTypeLabel': isEnglish ? 'Skill' : '技能',
    'status': 'running',
    'statusLabel': isEnglish ? 'Empty' : '空',
    'summary': summary,
    'progress': isEnglish
        ? 'Install or enable skills in Skill Store'
        : '请在技能商店安装或启用技能',
    'controlType': 'placeholder',
    'skillId': null,
    'skillName': null,
    'isPlaceholder': true,
  };
}

Map<String, dynamic> buildCodexSkillLoadingCard({bool isEnglish = false}) {
  return <String, dynamic>{
    'cardId': kCodexSkillLoadingCardId,
    'toolName': '@skill',
    'toolTitle': isEnglish ? 'Skills' : '技能',
    'displayName': isEnglish ? 'Skills' : '技能',
    'toolType': 'skill',
    'toolTypeLabel': isEnglish ? 'Skill' : '技能',
    'status': 'running',
    'statusLabel': isEnglish ? 'Loading' : '加载中',
    'summary': codexSkillPanelLoadingMessage(isEnglish: isEnglish),
    'progress': isEnglish ? 'Fetching skill catalog' : '正在拉取技能目录',
    'controlType': 'placeholder',
    'skillId': null,
    'skillName': null,
    'isPlaceholder': true,
  };
}

Map<String, dynamic> buildCodexSkillErrorCard(
  String error, {
  bool isEnglish = false,
}) {
  return <String, dynamic>{
    'cardId': kCodexSkillErrorCardId,
    'toolName': '@skill',
    'toolTitle': isEnglish ? 'Skills' : '技能',
    'displayName': isEnglish ? 'Skills' : '技能',
    'toolType': 'skill',
    'toolTypeLabel': isEnglish ? 'Skill' : '技能',
    'status': 'failed',
    'statusLabel': isEnglish ? 'Error' : '错误',
    'summary': codexSkillPanelErrorMessage(error, isEnglish: isEnglish),
    'progress': isEnglish ? 'Retry from Skill Store' : '可到技能商店重试',
    'controlType': 'placeholder',
    'skillId': null,
    'skillName': null,
    'isPlaceholder': true,
  };
}

/// Root-panel entry card that navigates into the skills sub-route (for M3).
Map<String, dynamic> buildCodexSkillsNavCard({
  bool isEnglish = false,
  int? skillCount,
}) {
  final countHint = skillCount == null
      ? (isEnglish ? 'Open skill list' : '打开技能列表')
      : (isEnglish
            ? '$skillCount skill${skillCount == 1 ? '' : 's'}'
            : '$skillCount 个技能');
  return <String, dynamic>{
    'cardId': 'slash-command-codex-skills',
    'toolName': '@skill',
    'toolTitle': isEnglish ? 'Skills' : '技能',
    'displayName': isEnglish ? 'Skills' : '技能',
    'toolType': 'command',
    'toolTypeLabel': isEnglish ? 'Skill' : '技能',
    'status': 'running',
    'statusLabel': isEnglish ? 'Browse' : '浏览',
    'summary': isEnglish
        ? 'Browse and insert skills with @name'
        : '浏览技能并以 @名称 插入',
    'progress': countHint,
    'controlType': 'nav',
    'nav': kCodexSkillPanelRouteName,
  };
}

/// Visible composer token for a selected skill.
String skillMentionToken(String skillName) {
  final trimmed = skillName.trim();
  if (trimmed.isEmpty) return '@skill';
  if (trimmed.startsWith('@')) return trimmed;
  return '@$trimmed';
}

/// True when [cardData] is a concrete skill selection (not empty/loading).
bool isCodexSkillSelectionCard(Map<String, dynamic> cardData) {
  if (cardData['isPlaceholder'] == true) return false;
  final skillId = cardData['skillId']?.toString().trim() ?? '';
  final skillName = cardData['skillName']?.toString().trim() ?? '';
  final cardId = cardData['cardId']?.toString() ?? '';
  if (skillId.isEmpty && skillName.isEmpty) return false;
  if (cardId == kCodexSkillEmptyCardId ||
      cardId == kCodexSkillLoadingCardId ||
      cardId == kCodexSkillErrorCardId) {
    return false;
  }
  return cardId.startsWith(kCodexSkillCardIdPrefix) ||
      cardData['toolType']?.toString() == 'skill';
}

String _oneLineSummary(String description) {
  final collapsed = description
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.isEmpty) return '';
  // Keep a single short line for the panel row.
  if (collapsed.length <= 96) return collapsed;
  return '${collapsed.substring(0, 93).trimRight()}…';
}

String _enabledStatusLabel({
  required bool enabled,
  required bool installed,
  required bool isEnglish,
}) {
  if (!installed) {
    return isEnglish ? 'Not installed' : '未安装';
  }
  return enabled
      ? (isEnglish ? 'Enabled' : '已启用')
      : (isEnglish ? 'Disabled' : '已禁用');
}

String _sourceTypeLabel(AgentSkillItem skill, {required bool isEnglish}) {
  if (skill.isBuiltin) {
    return isEnglish ? 'Builtin' : '内置';
  }
  if (skill.isOfficial) {
    return isEnglish ? 'Official' : '官方';
  }
  return isEnglish ? 'Skill' : '技能';
}
