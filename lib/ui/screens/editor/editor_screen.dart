import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell.dart';
import '../../../core/constants.dart';
import '../../../core/util.dart';
import '../../../domain/engines/analyzer.dart';
import '../../../domain/engines/highlighter.dart';
import '../../../domain/engines/search_engine.dart';
import '../../../domain/engines/token_estimator.dart';
import '../../../domain/models.dart';
import '../../../state/device_settings.dart';
import '../../../state/tokenizer_provider.dart';
import '../../../state/vault_notifier.dart';
import '../../prompt_export_sheet.dart';
import '../../search_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'code_editor.dart';
import 'editor_tools.dart';
import 'insights_panel.dart';
import 'quick_actions.dart';
import '../../widgets/pf_chrome.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> with WidgetsBindingObserver implements EditorHost {
  final _title = TextEditingController();
  final _body = HighlightingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  UndoHistoryController _undo = UndoHistoryController();
  int _docKey = 0;

  late final VaultNotifier _vault;

  Prompt? _prompt;
  String _category = 'custom';
  String _status = 'draft';
  String _format = 'text';
  List<String> _tags = [];
  List<PromptBlock>? _blocks;

  // last content known to be on disk (for external-change detection)
  String _baseTitle = '';
  String _baseBody = '';

  bool _dirty = false;
  bool _saving = false;
  Future<void>? _inflight;
  String? _saveError;
  Timer? _autosave;
  Timer? _suggestTimer;
  Timer? _scoreTimer;
  int? _liveScore;
  bool _insights = false;
  bool _showMeta = false;
  Prompt? _conflict;

  // find & replace
  bool _findOpen = false;
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  bool _matchCase = false;
  List<int> _matches = [];
  int _matchIdx = -1;

  // suggestions
  List<SuggestionItem> _suggestions = const [];
  int _sugReplaceStart = 0;
  int _sugReplaceEnd = 0;
  String _sugSuffix = '';

  @override
  void initState() {
    super.initState();
    _vault = ref.read(vaultProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _body.addListener(_onBodyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = ref.read(editorRequestProvider);
      if (r != null) _handleRequest(r);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave?.cancel();
    _suggestTimer?.cancel();
    _scoreTimer?.cancel();
    // Best-effort flush; the notifier outlives this widget.
    if (_dirty) unawaited(_persist());
    _body.removeListener(_onBodyChanged);
    _title.dispose();
    _body.dispose();
    _focus.dispose();
    _scroll.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      if (_dirty) unawaited(_persist());
    }
  }

  // ------------------------------------------------------------ EditorHost

  @override
  String get text => _body.text;
  @override
  String get format => _format;
  @override
  String get title => _title.text.trim().isEmpty ? 'Untitled prompt' : _title.text.trim();
  @override
  String? get promptId => _prompt?.id;

  @override
  void replaceText(String t) {
    _body.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _markDirty();
  }

  @override
  void insertAtCursor(String t) {
    final v = _body.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final start = sel.start < 0 ? v.text.length : sel.start;
    final end = sel.end < 0 ? v.text.length : sel.end;
    final next = v.text.replaceRange(start, end, t);
    _body.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + t.length));
    _markDirty();
  }

  @override
  void setFormat(String f) {
    setState(() => _format = f);
    _markDirty();
  }

  @override
  void openAsNew(String body, {String? title, String? format}) {
    unawaited(_openNew(seedBody: body, seedTitle: title, seedFormat: format));
  }

  @override
  void jumpToOffset(int offset) {
    _focus.requestFocus();
    _body.selection = TextSelection.collapsed(offset: offset.clamp(0, _body.text.length));
  }

  // ----------------------------------------------------------- load / save

  Future<void> _handleRequest(EditorRequest r) async {
    ref.read(editorRequestProvider.notifier).state = null;
    await _flush();
    if (!mounted) return;
    if (r.promptId != null) {
      final p = ref.read(vaultProvider).data.prompts[r.promptId];
      if (p != null) {
        _load(p);
        return;
      }
    }
    await _openNew(seedBody: r.seedBody, seedTitle: r.seedTitle, seedFormat: r.seedFormat, seedBlocks: r.seedBlocks);
  }

  Future<void> _openNew({String? seedBody, String? seedTitle, String? seedFormat, List<PromptBlock>? seedBlocks}) async {
    await _flush();
    if (!mounted) return;
    _resetDoc();
    _prompt = null;
    _title.text = seedTitle ?? '';
    _setBody(seedBody ?? '');
    _format = seedFormat ?? 'text';
    _category = 'custom';
    _status = 'draft';
    _tags = [];
    _blocks = seedBlocks?.map((b) => b.clone()).toList();
    _baseTitle = '';
    _baseBody = '';
    _conflict = null;
    _saveError = null;
    setState(() {});
    // seeded content is unsaved until it is written
    if ((seedBody ?? '').isNotEmpty || (seedTitle ?? '').isNotEmpty) {
      _markDirty();
    }
    _scheduleSuggestions();
    _scheduleLiveScore();
  }

  void _load(Prompt p) {
    _resetDoc();
    _prompt = p;
    _title.text = p.title;
    _setBody(p.body);
    _category = p.category;
    _status = p.status;
    _format = p.format;
    _tags = List.of(p.tags);
    _blocks = p.blocks?.map((b) => b.clone()).toList();
    _baseTitle = p.title;
    _baseBody = p.body;
    _dirty = false;
    _conflict = null;
    _saveError = null;
    setState(() {});
    _runFind();
  }

  void _resetDoc() {
    _autosave?.cancel();
    _undo = UndoHistoryController();
    _docKey++;
    _dirty = false;
    _suggestions = const [];
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _markDirty() {
    _dirty = true;
    _saveError = null;
    _autosave?.cancel();
    _autosave = Timer(Duration(milliseconds: ref.read(deviceSettingsProvider).autosaveMs), () => unawaited(_persist()));
    if (mounted) setState(() {});
  }

  void _onBodyChanged() {
    // The controller notifies for selection moves too; only text edits dirty the doc.
    if (_body.text != _lastSeenText) {
      _lastSeenText = _body.text;
      _syncWords();
      _markDirty();
      if (_findOpen) _runFind(keepIndex: true);
    }
    _scheduleSuggestions();
    _scheduleLiveScore();
  }

  String _lastSeenText = '';

  /// Sets the body without marking the document dirty.
  void _syncWords() {
    final n = RegExp(r'\S+').allMatches(_body.text).length;
    Future.microtask(() {
      if (mounted) ref.read(editorWordsProvider.notifier).state = n;
    });
  }

  void _setBody(String t) {
    _lastSeenText = t;
    _body.text = t;
    _syncWords();
  }

  Future<void> _flush() async {
    _autosave?.cancel();
    if (_dirty) await _persist();
  }

  Future<void> _persist() async {
    _autosave?.cancel();
    while (_saving) {
      await (_inflight ?? Future<void>.value());
    }
    if (!_dirty) return;
    final title = _title.text.trim();
    final body = _body.text;
    if (_prompt == null && title.isEmpty && body.trim().isEmpty) {
      _dirty = false;
      return;
    }
    final stored = _prompt == null ? null : _vault.prompt(_prompt!.id);
    final base = stored ?? _prompt;
    final p = (base ?? Prompt()).clone()
      ..title = title
      ..body = body
      ..category = _category
      ..status = _status
      ..format = _format
      ..tags = List.of(_tags)
      ..blocks = _blocks?.map((b) => b.clone()).toList();
    _saving = true;
    _dirty = false;
    final done = Completer<void>();
    _inflight = done.future;
    try {
      final saved = await _vault.savePrompt(p);
      _prompt = saved;
      _baseTitle = saved.title;
      _baseBody = saved.body;
      _saveError = null;
    } catch (e) {
      _dirty = true;
      _saveError = '$e';
    } finally {
      _saving = false;
      done.complete();
      if (mounted) setState(() {});
    }
  }

  void _onVaultChanged(VaultState? prev, VaultState next) {
    final cur = _prompt;
    if (cur == null || _saving) return;
    final stored = next.data.prompts[cur.id];
    if (stored == null) {
      if (prev?.data.prompts.containsKey(cur.id) ?? false) {
        _prompt = null;
        _baseBody = '';
        _baseTitle = '';
        if (mounted) {
          toast(context, 'This prompt was removed from the folder. Your text is kept; editing re-creates it.');
          if (_body.text.trim().isNotEmpty) _markDirty();
        }
      }
      return;
    }
    if (stored.body == _baseBody && stored.title == _baseTitle) {
      // metadata-only change elsewhere
      if (!_dirty) {
        setState(() {
          _category = stored.category;
          _status = stored.status;
          _format = stored.format;
          _tags = List.of(stored.tags);
          _prompt = stored;
        });
      }
      return;
    }
    // content changed on disk (e.g. edited in Obsidian, restored from history, synced)
    if (!_dirty && _body.text == _baseBody && _title.text == _baseTitle) {
      _load(stored);
      toast(context, 'Reloaded: the file changed on disk');
    } else {
      setState(() => _conflict = stored);
    }
  }

  // ------------------------------------------------------------ suggestions

  /// Debounced live analyzer score (Settings > Live analyzer). Off: the chip disappears and no analysis runs.
  void _scheduleLiveScore() {
    _scoreTimer?.cancel();
    if (!ref.read(deviceSettingsProvider).analyzerLive) {
      if (_liveScore != null) setState(() => _liveScore = null);
      return;
    }
    _scoreTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final t = _body.text;
      final v = t.trim().isEmpty ? null : Analyzer.analyze(t, profileId: ref.read(vaultProvider).data.settings.scoringProfile).overall.round();
      if (v != _liveScore) setState(() => _liveScore = v);
    });
  }

  void _scheduleSuggestions() {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 120), _computeSuggestions);
  }

  void _computeSuggestions() {
    if (!mounted) return;
    void clear() {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
    }
    if (!ref.read(deviceSettingsProvider).suggestionsEnabled) {
      clear();
      return;
    }

    final sel = _body.selection;
    if (!_focus.hasFocus || !sel.isValid || !sel.isCollapsed || sel.baseOffset > _body.text.length) return clear();
    final cursor = sel.baseOffset;
    final before = _body.text.substring(0, cursor);
    final after = _body.text.substring(cursor);
    final state = ref.read(vaultProvider);

    // 1) insertion triggers: / // /// \ \\ @
    final trig = TriggerDetector.detect(before);
    if (trig != null) {
      final kind = TriggerDetector.kindForPrefix(trig.prefix);
      if (kind != null) {
        final items = TriggerDetector.candidatesFor(kind, trig.query, state.data);
        _sugReplaceStart = cursor - trig.fullMatch.length;
        _sugReplaceEnd = cursor;
        _sugSuffix = '';
        setState(() => _suggestions = items);
        return;
      }
    }
    // 2) variable names inside {{ }}
    final vm = RegExp(r'\{\{\s*([a-zA-Z0-9_]*)$').firstMatch(before);
    final hub = ref.read(suggestionHubProvider);
    final engine = hub.fresh(state);
    if (vm != null) {
      final partial = vm.group(1) ?? '';
      final items = engine.variableSuggestions(partial);
      _sugReplaceStart = cursor - partial.length;
      _sugReplaceEnd = cursor;
      _sugSuffix = after.startsWith('}}') ? '' : '}}';
      setState(() => _suggestions = items);
      return;
    }
    // 3) learned phrase / word completion
    if (before.trim().length < 3) return clear();
    final items = engine.phraseSuggestions(before);
    if (items.isEmpty) return clear();
    final matchLen = items.first.matchLen;
    _sugReplaceStart = cursor - matchLen;
    _sugReplaceEnd = cursor;
    _sugSuffix = '';
    setState(() => _suggestions = items);
  }

  void _acceptSuggestion(SuggestionItem s) {
    final t = _body.text;
    final start = _sugReplaceStart.clamp(0, t.length);
    final end = _sugReplaceEnd.clamp(start, t.length);
    // word completion replaces the typed prefix; per-item matchLen can differ from the first item's
    final replaceStart = (s.src == 'word' || s.src == 'phrase') ? (end - s.matchLen).clamp(0, end) : start;
    final ins = '${s.text}$_sugSuffix';
    final next = t.replaceRange(replaceStart, end, ins);
    _body.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: replaceStart + ins.length));
    setState(() => _suggestions = const []);
    if (s.src == 'snippet' && s.meta != null) {
      final sn = ref.read(vaultProvider).data.snippets[s.meta];
      if (sn != null) unawaited(_vault.saveSnippet(sn.clone()..useCount += 1));
    }
  }

  void _quickInsert(String token) {
    final t = _body.text;
    final sel = _body.selection;
    final pos = sel.isValid ? sel.start : t.length;
    final needsSpace = pos > 0 && !RegExp(r'\s').hasMatch(t[pos - 1]);
    insertAtCursor('${needsSpace ? ' ' : ''}$token');
    _focus.requestFocus();
  }

  // ---------------------------------------------------------------- find

  void _runFind({bool keepIndex = false}) {
    final q = _findCtrl.text;
    final matches = <int>[];
    if (q.isNotEmpty) {
      final hay = _matchCase ? _body.text : _body.text.toLowerCase();
      final needle = _matchCase ? q : q.toLowerCase();
      var i = hay.indexOf(needle);
      while (i != -1 && matches.length < 5000) {
        matches.add(i);
        i = hay.indexOf(needle, i + (needle.isEmpty ? 1 : needle.length));
      }
    }
    setState(() {
      _matches = matches;
      if (matches.isEmpty) {
        _matchIdx = -1;
      } else if (!keepIndex || _matchIdx < 0 || _matchIdx >= matches.length) {
        _matchIdx = 0;
      }
    });
  }

  void _gotoMatch(int delta) {
    if (_matches.isEmpty) return;
    _matchIdx = (_matchIdx + delta) % _matches.length;
    if (_matchIdx < 0) _matchIdx += _matches.length;
    final start = _matches[_matchIdx];
    _focus.requestFocus();
    _body.selection = TextSelection(baseOffset: start, extentOffset: start + _findCtrl.text.length);
    setState(() {});
  }

  void _replaceOne() {
    if (_matches.isEmpty || _matchIdx < 0) return;
    final start = _matches[_matchIdx];
    final len = _findCtrl.text.length;
    final t = _body.text.replaceRange(start, start + len, _replaceCtrl.text);
    _body.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: start + _replaceCtrl.text.length));
    _runFind(keepIndex: true);
  }

  void _replaceAll() {
    final q = _findCtrl.text;
    if (q.isEmpty || _matches.isEmpty) return;
    final n = _matches.length;
    final re = RegExp(RegExp.escape(q), caseSensitive: _matchCase);
    final t = _body.text.replaceAll(re, _replaceCtrl.text);
    _body.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _runFind();
    toast(context, 'Replaced $n occurrence${n == 1 ? '' : 's'}');
  }

  // --------------------------------------------------------------- actions

  Future<void> _saveVersion() async {
    final note = await textPrompt(context, title: 'Save version', label: 'Note (optional)', confirmLabel: 'Save version');
    if (note == null) return;
    await _flush();
    final id = _prompt?.id;
    if (id == null) {
      if (mounted) toast(context, 'Write something first');
      return;
    }
    final v = await _vault.createVersion(id, note: note);
    if (!mounted) return;
    setState(() => _prompt = ref.read(vaultProvider).data.prompts[id] ?? _prompt);
    toast(context, v == null ? 'Could not save version' : 'Saved as v${v.versionNum}');
  }

  Future<void> _copyText() async {
    await copyToClipboard(context, _body.text);
    final id = _prompt?.id;
    if (id != null) await _vault.incrementUse(id);
  }

  Future<void> _menu(String v) async {
    final id = _prompt?.id;
    switch (v) {
      case 'new':
        await _openNew();
        break;
      case 'find':
        setState(() => _findOpen = !_findOpen);
        if (_findOpen) _runFind();
        break;
      case 'zen':
        ref.read(zenModeProvider.notifier).state = !ref.read(zenModeProvider);
        break;
      case 'version':
        await _saveVersion();
        break;
      case 'history':
        await _flush();
        if (!mounted) return;
        if (_prompt == null) {
          toast(context, 'Nothing saved yet');
        } else {
          context.push('/history?id=${_prompt!.id}');
        }
        break;
      case 'copy':
        await _copyText();
        break;
      case 'export':
        await _flush();
        if (_prompt != null && mounted) await showPromptExportSheet(context, ref, _prompt!);
        break;
      case 'fav':
        await _flush();
        if (id != null) await _vault.toggleFavorite(id);
        break;
      case 'pin':
        await _flush();
        if (id != null) await _vault.togglePinned(id);
        break;
      case 'revisit':
        await _flush();
        if (_prompt == null) return;
        final cur = ref.read(vaultProvider).data.prompts[_prompt!.id];
        if (cur?.needsRevisit != null) {
          await _vault.clearRevisit(_prompt!.id);
        } else {
          final note = await textPrompt(context, title: 'Flag for revisit', label: 'What needs another look?', confirmLabel: 'Flag');
          if (note != null) await _vault.flagRevisit(_prompt!.id, note.trim());
        }
        break;
      case 'duplicate':
        await _flush();
        if (id != null) {
          final copy = await _vault.duplicatePrompt(id);
          _load(copy);
          if (mounted) toast(context, 'Duplicated');
        }
        break;
      case 'template':
        final name = await textPrompt(context, title: 'Save as template', label: 'Template name', initial: _title.text.trim(), confirmLabel: 'Save');
        if (name != null && name.trim().isNotEmpty) {
          await _vault.saveTemplate(Template(name: name.trim(), body: _body.text, category: _category));
          if (mounted) toast(context, 'Saved to Templates/');
        }
        break;
      case 'snippet':
        final sel = _body.selection;
        final chosen = sel.isValid && !sel.isCollapsed ? sel.textInside(_body.text) : _body.text;
        final trig = await textPrompt(context, title: 'Save as snippet', label: 'Trigger (e.g. /sig)', initial: '/', confirmLabel: 'Save');
        if (trig != null) {
          var t = trig.trim().replaceAll(RegExp(r'\s+'), '');
          if (t.isEmpty || t == '/') return;
          if (!t.startsWith('/')) t = '/$t';
          await _vault.saveSnippet(Snippet(trigger: t, body: chosen));
          if (mounted) toast(context, 'Snippet $t saved');
        }
        break;
      case 'related':
        await _showRelated();
        break;
      case 'delete':
        if (id == null) {
          await _openNew();
          return;
        }
        final ok = await confirmDialog(context, title: 'Delete prompt?', message: 'This removes the file and its version history from your folder.', confirmLabel: 'Delete', destructive: true);
        if (ok) {
          _autosave?.cancel();
          _dirty = false;
          await _vault.deletePrompt(id);
          await _openNew();
        }
        break;
    }
  }

  Future<void> _showRelated() async {
    final d = ref.read(vaultProvider).data;
    final id = _prompt?.id ?? '';
    final related = SearchEngine.relatedTo(d, id, _body.text);
    final backlinks = _prompt == null
        ? <Prompt>[]
        : d.prompts.values.where((x) => !x.archived && x.id != id && x.body.toLowerCase().contains('[[${_prompt!.displayTitle.toLowerCase()}]]')).toList();
    await showPfSheet<void>(
      context,
      title: 'Related',
      builder: (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 20), children: [
        const SectionTitle('Similar prompts'),
        if (related.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Nothing similar yet.')),
        for (final r in related)
          ListTile(
            title: Text(r.prompt.displayTitle),
            subtitle: Text('${(r.sim * 100).round()}% similar'),
            onTap: () {
              Navigator.pop(ctx);
              openInEditor(context, ref, promptId: r.prompt.id);
            },
          ),
        const SectionTitle('Linked from (backlinks)'),
        if (backlinks.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No prompt links here with [[wiki links]].')),
        for (final b in backlinks)
          ListTile(
            title: Text(b.displayTitle),
            onTap: () {
              Navigator.pop(ctx);
              openInEditor(context, ref, promptId: b.id);
            },
          ),
      ]),
    );
  }

  Future<void> _pickCategory() async {
    final c = await showPfSheet<String>(
      context,
      title: 'Category',
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final cat in kCategories) ListTile(leading: CircleAvatar(radius: 6, backgroundColor: pfColor(cat.color)), title: Text(cat.label), selected: cat.id == _category, onTap: () => Navigator.pop(ctx, cat.id)),
      ]),
    );
    if (c != null) {
      setState(() => _category = c);
      _markDirty();
    }
  }

  Future<void> _pickStatus() async {
    final s = await showPfSheet<String>(
      context,
      title: 'Status',
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final st in kStatuses) ListTile(leading: CircleAvatar(radius: 6, backgroundColor: pfColor(st.color)), title: Text(st.label), selected: st.id == _status, onTap: () => Navigator.pop(ctx, st.id)),
      ]),
    );
    if (s != null) {
      setState(() => _status = s);
      _markDirty();
    }
  }

  Future<void> _pickFormat() async {
    final f = await showPfSheet<String>(
      context,
      title: 'Prompt format',
      builder: (ctx) => ListView(shrinkWrap: true, children: [
        for (final o in kPromptFormats) ListTile(title: Text(o.label), selected: o.id == _format, onTap: () => Navigator.pop(ctx, o.id)),
      ]),
    );
    if (f != null) setFormat(f);
  }

  Future<void> _editTags() async {
    final all = <String>{for (final p in ref.read(vaultProvider).data.prompts.values) ...p.tags}.toList()..sort();
    final ctrl = TextEditingController();
    await showPfSheet<void>(
      context,
      title: 'Tags',
      builder: (ctx) => StatefulBuilder(builder: (c, setSheet) {
        void add(String raw) {
          final t = raw.trim().replaceAll(RegExp(r'^#+'), '').replaceAll(RegExp(r'\s+'), '-').toLowerCase();
          if (t.isEmpty || _tags.contains(t)) return;
          setState(() => _tags = [..._tags, t]);
          _markDirty();
          setSheet(() {});
          ctrl.clear();
        }

        final suggestions = all.where((t) => !_tags.contains(t)).take(20).toList();
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
          TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Add a tag and press enter'), onSubmitted: add, textInputAction: TextInputAction.done),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final t in _tags)
              InputChip(
                label: Text('#$t'),
                onDeleted: () {
                  setState(() => _tags = _tags.where((x) => x != t).toList());
                  _markDirty();
                  setSheet(() {});
                },
              ),
          ]),
          if (suggestions.isNotEmpty) ...[
            const SectionTitle('Existing tags'),
            Wrap(spacing: 8, runSpacing: 4, children: [for (final t in suggestions) ActionChip(label: Text('#$t'), onPressed: () => add(t))]),
          ],
        ]);
      }),
    );
    ctrl.dispose();
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen<EditorRequest?>(editorRequestProvider, (_, next) {
      if (next != null) unawaited(_handleRequest(next));
    });
    ref.listen<VaultState>(vaultProvider, _onVaultChanged);

    final p = context.pf;
    final ds = ref.watch(deviceSettingsProvider);
    final zen = ref.watch(zenModeProvider);
    final vault = ref.watch(vaultProvider);
    final stored = _prompt == null ? null : vault.data.prompts[_prompt!.id];
    final family = (kEditorFontFallbacks[ds.editorFont] ?? kMonoFallback);
    _body.configure(format: _format, highlight: ds.highlight, colors: p.brightness == Brightness.dark ? const HighlightColors.dark() : const HighlightColors.light());
    final cat = categoryById(_category);
    final status = statusById(_status);

    final fmtLabel = kPromptFormats.firstWhere((f) => f.id == _format, orElse: () => kPromptFormats.first).label;
    final kbOpen = View.of(context).viewInsets.bottom > 0;
    MediaQuery.of(context); // rebuild when the keyboard opens/closes
    final trailing = <Widget>[
      IconButton(tooltip: 'Find & replace', visualDensity: VisualDensity.compact, icon: const Icon(Icons.search, size: 20), onPressed: () => _menu('find')),
      ValueListenableBuilder<UndoHistoryValue>(
        valueListenable: _undo,
        builder: (context, v, _) => Row(children: [
          IconButton(tooltip: 'Undo', visualDensity: VisualDensity.compact, icon: const Icon(Icons.undo, size: 20), onPressed: v.canUndo ? _undo.undo : null),
          IconButton(tooltip: 'Redo', visualDensity: VisualDensity.compact, icon: const Icon(Icons.redo, size: 20), onPressed: v.canRedo ? _undo.redo : null),
        ]),
      ),
      IconButton(tooltip: 'Category, status & tags', visualDensity: VisualDensity.compact, icon: Icon(Icons.label_outline, size: 20, color: _showMeta ? p.amber : null), onPressed: () => setState(() => _showMeta = !_showMeta)),
      IconButton(tooltip: 'DNA & analyzer', visualDensity: VisualDensity.compact, icon: Icon(Icons.insights_outlined, size: 20, color: _insights ? p.amber : null), onPressed: () => setState(() => _insights = !_insights)),
      IconButton(tooltip: 'Zen mode', visualDensity: VisualDensity.compact, icon: const Icon(Icons.fullscreen, size: 21), onPressed: () => _menu('zen')),
      IconButton(tooltip: 'New prompt', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add, size: 22), onPressed: () => _menu('new')),
      PopupMenuButton<String>(
                    onSelected: _menu,
        padding: EdgeInsets.zero,
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'new', child: Text('New prompt')),
                      const PopupMenuItem(value: 'find', child: Text('Find & replace')),
                      const PopupMenuItem(value: 'zen', child: Text('Zen mode')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'version', child: Text('Save version…')),
                      const PopupMenuItem(value: 'history', child: Text('Version history')),
                      const PopupMenuItem(value: 'related', child: Text('Related & backlinks')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'copy', child: Text('Copy text')),
                      const PopupMenuItem(value: 'export', child: Text('Export / share…')),
                      PopupMenuItem(value: 'fav', child: Text(stored?.favorite == true ? 'Remove favorite' : 'Favorite')),
                      PopupMenuItem(value: 'pin', child: Text(stored?.pinned == true ? 'Unpin' : 'Pin to top')),
                      PopupMenuItem(value: 'revisit', child: Text(stored?.needsRevisit != null ? 'Clear revisit flag' : 'Flag for revisit…')),
                      const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'template', child: Text('Save as template…')),
                      const PopupMenuItem(value: 'snippet', child: Text('Save as snippet…')),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
    ];

    return PopScope(
      canPop: !zen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && zen) ref.read(zenModeProvider.notifier).state = false;
      },
      child: Scaffold(
        backgroundColor: p.editorBg,
        body: SafeArea(
          top: zen,
          child: Column(children: [
            if (!zen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _title,
                      onChanged: (_) => _markDirty(),
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                      decoration: const InputDecoration(hintText: 'Untitled prompt', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _pickFormat,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 12, right: 6),
                      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(fmtLabel, style: const TextStyle(fontSize: 13.5)),
                        const SizedBox(width: 6),
                        Icon(Icons.keyboard_arrow_down, size: 18, color: p.textTertiary),
                      ]),
                    ),
                  ),
                ]),
              ),
            if (!zen && _showMeta)
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  _metaChip(cat.label, pfColor(cat.color), _pickCategory),
                  _metaChip(status.label, pfColor(status.color), _pickStatus),
                  _metaChip(kPromptFormats.firstWhere((f) => f.id == _format, orElse: () => kPromptFormats.first).label, p.blue, _pickFormat),
                  _metaChip(_tags.isEmpty ? '+ tags' : _tags.map((t) => '#$t').join(' '), p.textSecondary, _editTags),
                ]),
              ),
            if (!zen)
              EditorQuickActions(
                host: this,
                compact: kbOpen,
                leading: [
                  PfBtn(label: 'Save', icon: Icons.save_outlined, onPressed: () => unawaited(_persist())),
                  PfBtn(label: 'Download', icon: Icons.file_download_outlined, onPressed: () => _menu('export')),
                  PfBtn(label: 'Save version', icon: Icons.history_toggle_off, onPressed: () => _menu('version')),
                  _SaveIndicator(dirty: _dirty, saving: _saving, error: _saveError != null, saved: stored != null),
                ],
                trailing: trailing,
              ),
            if (_saveError != null)
              MaterialBanner(
                backgroundColor: p.red.withOpacity(0.12),
                content: Text('Could not save to your folder: $_saveError', style: const TextStyle(fontSize: 13)),
                actions: [
                  TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _body.text)), child: const Text('Copy text')),
                  TextButton(onPressed: () => unawaited(_persist()), child: const Text('Retry')),
                ],
              ),
            if (_conflict != null)
              MaterialBanner(
                backgroundColor: p.amber.withOpacity(0.12),
                content: const Text('This file changed on disk while you were editing.', style: TextStyle(fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () {
                      final c = _conflict!;
                      setState(() => _conflict = null);
                      // keep my text: adopt the disk version as the new base so my next save overwrites it
                      _baseBody = c.body;
                      _baseTitle = c.title;
                      _prompt = c;
                      _markDirty();
                    },
                    child: const Text('Keep mine'),
                  ),
                  TextButton(
                    onPressed: () {
                      final c = _conflict!;
                      _load(c);
                    },
                    child: const Text('Load disk version'),
                  ),
                ],
              ),
            if (_findOpen && !zen) _findBar(p),
            Expanded(
              flex: 5,
              child: CodeEditor(
                key: ValueKey(_docKey),
                controller: _body,
                focusNode: _focus,
                undoController: _undo,
                fontFamily: family.first,
                fontFallback: family,
                fontSize: ds.editorFontSize,
                lineNumbers: ds.lineNumbers,
                wordWrap: ds.wordWrap,
                lineHeight: ds.lineHeight == 'compact' ? 1.4 : (ds.lineHeight == 'loose' ? 2.0 : 1.7),
                tabWidth: ds.tabWidth,
                popup: _suggestions.isNotEmpty ? _suggestionStrip(p) : null,
                popupHeight: (_suggestions.length > 7 ? 7 : _suggestions.length) * 42.0,
                scrollController: _scroll,
                hint: 'Write your prompt…  Try / for snippets, // for prompts, @ for links, {{ for variables.',
              ),
            ),
            if (_insights && !zen)
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _body,
                    builder: (context, v, _) => EditorInsights(
                      text: v.text,
                      blocks: _blocks,
                      profileId: ref.watch(vaultProvider).data.settings.scoringProfile,
                      onProfile: (id) => ref.read(vaultProvider.notifier).updateSettings(ref.read(vaultProvider).data.settings.clone()..scoringProfile = id),
                    ),
                  ),
                ),
              ),
            _bottomBar(p, ds, zen),
          ]),
        ),
      ),
    );
  }

  Widget _metaChip(String label, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
        child: PfChip(label: label, color: color, selected: true, onTap: onTap),
      );

  Widget _findBar(PfPalette p) => Container(
        color: p.surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _findCtrl,
                onChanged: (_) => _runFind(),
                onSubmitted: (_) => _gotoMatch(1),
                decoration: InputDecoration(isDense: true, hintText: 'Find', suffixText: _matches.isEmpty ? (_findCtrl.text.isEmpty ? '' : '0') : '${_matchIdx + 1}/${_matches.length}'),
              ),
            ),
            IconButton(tooltip: 'Previous', icon: const Icon(Icons.keyboard_arrow_up), onPressed: () => _gotoMatch(-1)),
            IconButton(tooltip: 'Next', icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => _gotoMatch(1)),
            IconButton(
              tooltip: 'Match case',
              icon: Icon(Icons.text_fields, color: _matchCase ? p.amber : null),
              onPressed: () {
                setState(() => _matchCase = !_matchCase);
                _runFind();
              },
            ),
            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => setState(() => _findOpen = false)),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: _replaceCtrl, decoration: const InputDecoration(isDense: true, hintText: 'Replace with'))),
            TextButton(onPressed: _matches.isEmpty ? null : _replaceOne, child: const Text('Replace')),
            TextButton(onPressed: _matches.isEmpty ? null : _replaceAll, child: const Text('All')),
          ]),
        ]),
      );

  /// Dropdown-style completion list (like the web editor): the typed word's best matches, each with a type tag.
  Widget _suggestionStrip(PfPalette p) {
    final shown = _suggestions.take(7).toList();
    final mono = TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 14, color: p.text);
    return Container(
      constraints: const BoxConstraints(maxHeight: 294),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < shown.length; i++)
            InkWell(
              onTap: () => _acceptSuggestion(shown[i]),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: i == 0 ? p.amber.withOpacity(0.10) : null,
                  border: Border(left: BorderSide(color: i == 0 ? p.amber : Colors.transparent, width: 3)),
                ),
                child: Row(children: [
                  Expanded(child: Text(Utils.truncate(shown[i].label.replaceAll('\n', ' '), 44), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono)),
                  const SizedBox(width: 12),
                  Text(shown[i].src.toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: p.textTertiary)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(String src) {
    switch (src) {
      case 'snippet':
        return Icons.bolt;
      case 'prompt':
        return Icons.description_outlined;
      case 'pattern':
        return Icons.account_tree_outlined;
      case 'template':
        return Icons.dashboard_customize_outlined;
      case 'block':
        return Icons.view_agenda_outlined;
      case 'link':
        return Icons.link;
      case 'variable':
        return Icons.data_object;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  Widget _bottomBar(PfPalette p, DeviceSettings ds, bool zen) {
    final d = ref.watch(vaultProvider).data;
    ref.watch(tokenizerProvider);
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (final t in const [
                ['/', 'snippet'],
                ['//', 'prompt'],
                ['///', 'pattern'],
                ['\\', 'template'],
                ['\\\\', 'block'],
                ['@', 'link'],
                ['{{}}', 'variable'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${t[0]} ${t[1]}', style: TextStyle(fontSize: 12, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback)),
                    onPressed: () {
                      if (t[0] == '{{}}') {
                        insertAtCursor('{{}}');
                        final off = _body.selection.baseOffset - 2;
                        _body.selection = TextSelection.collapsed(offset: off);
                        _focus.requestFocus();
                      } else {
                        _quickInsert(t[0]);
                      }
                    },
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _body,
              builder: (context, v, _) {
                final words = Utils.countWords(v.text);
                final tok = TokenEstimator.estimateTokens(v.text, d.settings.selectedModel, d.settings.customModels);
                final ctx = TokenEstimator.contextStatus(v.text, d.settings.selectedModel, d.settings.customModels);
                final overWords = ds.wordCountWarning > 0 && words > ds.wordCountWarning;
                final color = overWords || ctx.level == 'over' ? (ctx.level == 'over' ? p.red : p.amber) : (ctx.level == 'warn' ? p.amber : p.textSecondary);
                final exact = TokenEstimator.isExact(d.settings.selectedModel, d.settings.customModels);
                return Row(children: [
                  if (_liveScore != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: 'Live analyzer score',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: scoreColor(context, _liveScore!).withOpacity(0.16), borderRadius: BorderRadius.circular(10)),
                          child: Text('$_liveScore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scoreColor(context, _liveScore!))),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      overWords
                          ? '$words words — over your ${ds.wordCountWarning}-word limit · ${exact ? '' : '~'}$tok tokens'
                          : '$words words · ${v.text.length} chars · ${exact ? '' : '~'}$tok tokens',
                      style: TextStyle(fontSize: 12, color: color, fontWeight: overWords ? FontWeight.w700 : FontWeight.w400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(tooltip: 'Find & replace', icon: const Icon(Icons.find_in_page_outlined, size: 22), onPressed: () => _menu('find')),
                  IconButton(tooltip: zen ? 'Exit Zen mode' : 'Zen mode', icon: Icon(zen ? Icons.fullscreen_exit : Icons.fullscreen, size: 22), onPressed: () => _menu('zen')),
                  IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy, size: 20), onPressed: _copyText),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Tools'),
                    onPressed: () async {
                      FocusScope.of(context).unfocus();
                      await showEditorTools(context, this);
                    },
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _SaveIndicator extends StatelessWidget {
  final bool dirty;
  final bool saving;
  final bool error;
  final bool saved;
  const _SaveIndicator({required this.dirty, required this.saving, required this.error, required this.saved});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    IconData icon;
    Color color;
    String tip;
    if (error) {
      icon = Icons.error_outline;
      color = p.red;
      tip = 'Save failed';
    } else if (saving || dirty) {
      icon = Icons.sync;
      color = p.amber;
      tip = 'Saving…';
    } else if (saved) {
      icon = Icons.check_circle_outline;
      color = p.green;
      tip = 'Saved to folder';
    } else {
      icon = Icons.edit_outlined;
      color = p.textTertiary;
      tip = 'Not saved yet';
    }
    return Tooltip(message: tip, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(icon, size: 18, color: color)));
  }
}
