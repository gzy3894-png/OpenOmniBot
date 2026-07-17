enum CodexSlashSubmitKind {
  none,
  openModelPicker,
  selectModel,
  startReview,
  startInit,
  togglePlan,
  startPlan,
  /// Thread compact RPC only — never Fast / auto-compaction conf.
  startCompact,
  /// B34: Fast mode toggle (`serviceTier` / conf `fast_mode`) — never compact.
  toggleFast,
  /// B33/B34: conf `features.auto_compaction` only — never thread compact RPC.
  toggleAutoCompact,
  showStatus,
  showDiff,
  stopTurn,
  startNew,
  resumeThread,
  setGoal,
  clearGoal,
  showGoal,
  /// Invoke one or more skills: `/skill <name>[ <prompt>]`.
  startSkill,
  unsupported,
}

class CodexSlashSubmitIntent {
  const CodexSlashSubmitIntent(this.kind, {this.value});

  final CodexSlashSubmitKind kind;
  final String? value;
}

CodexSlashSubmitIntent resolveCodexSlashSubmitIntent(String messageText) {
  final trimmed = messageText.trim();
  if (!trimmed.startsWith('/')) {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.none);
  }

  final normalized = trimmed.toLowerCase();
  if (normalized == '/model') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.openModelPicker);
  }
  if (normalized.startsWith('/model ')) {
    final modelId = trimmed.substring('/model'.length).trim();
    if (modelId.isEmpty) {
      return const CodexSlashSubmitIntent(CodexSlashSubmitKind.openModelPicker);
    }
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.selectModel,
      value: modelId,
    );
  }

  if (normalized == '/review') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.startReview);
  }
  // B5: `/review <附言>` keeps startReview + value; handler maps value to
  // review target {type:custom, instructions}. Bare → uncommittedChanges.
  if (normalized.startsWith('/review ')) {
    final prompt = trimmed.substring('/review'.length).trim();
    if (prompt.isEmpty) {
      return const CodexSlashSubmitIntent(CodexSlashSubmitKind.startReview);
    }
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.startReview,
      value: prompt,
    );
  }
  if (normalized == '/init') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.startInit);
  }
  if (normalized == '/plan') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.togglePlan);
  }
  if (normalized.startsWith('/plan ')) {
    final prompt = trimmed.substring('/plan'.length).trim();
    if (prompt.isEmpty) {
      return const CodexSlashSubmitIntent(CodexSlashSubmitKind.togglePlan);
    }
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.startPlan,
      value: prompt,
    );
  }

  if (normalized == '/compact') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.startCompact);
  }
  // B34: Fast / auto-compact / compact are three-way exclusive kinds.
  if (normalized == '/fast') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.toggleFast);
  }
  if (normalized == '/auto-compact' || normalized == '/auto-compaction') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.toggleAutoCompact);
  }
  if (normalized == '/status') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.showStatus);
  }
  if (normalized == '/diff') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.showDiff);
  }
  if (normalized == '/stop' || normalized == '/clean') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.stopTurn);
  }
  if (normalized == '/new' || normalized == '/clear') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.startNew);
  }
  if (normalized == '/resume' || normalized.startsWith('/resume ')) {
    final threadId = trimmed.length > '/resume'.length
        ? trimmed.substring('/resume'.length).trim()
        : '';
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.resumeThread,
      value: threadId.isEmpty ? null : threadId,
    );
  }
  if (normalized == '/goal') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.showGoal);
  }
  if (normalized == '/goal clear' || normalized == '/goal --clear') {
    return const CodexSlashSubmitIntent(CodexSlashSubmitKind.clearGoal);
  }
  if (normalized.startsWith('/goal ')) {
    final objective = trimmed.substring('/goal'.length).trim();
    if (objective.isEmpty) {
      return const CodexSlashSubmitIntent(CodexSlashSubmitKind.showGoal);
    }
    if (objective.toLowerCase() == 'clear' ||
        objective.toLowerCase() == '--clear') {
      return const CodexSlashSubmitIntent(CodexSlashSubmitKind.clearGoal);
    }
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.setGoal,
      value: objective,
    );
  }

  if (normalized == '/skill') {
    return const CodexSlashSubmitIntent(
      CodexSlashSubmitKind.startSkill,
      value: '',
    );
  }
  if (normalized.startsWith('/skill ')) {
    final args = trimmed.substring('/skill'.length).trim();
    return CodexSlashSubmitIntent(
      CodexSlashSubmitKind.startSkill,
      value: args,
    );
  }

  return const CodexSlashSubmitIntent(CodexSlashSubmitKind.unsupported);
}
