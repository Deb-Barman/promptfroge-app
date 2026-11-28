import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell.dart';
import '../../../core/constants.dart';
import '../../../core/util.dart';
import '../../../domain/engines/analyzer.dart';
import '../../../domain/engines/brain.dart';
import '../../../domain/engines/highlighter.dart';
import '../../../domain/engines/search_engine.dart';
import '../../../domain/engines/token_estimator.dart';
import '../../../domain/models.dart';
import '../../../state/brain_provider.dart';
import '../../../state/device_settings.dart';
import '../../../state/tokenizer_provider.dart';
import '../../../state/vault_notifier.dart';
import '../../prompt_export_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brain_sheet.dart';
import '../../widgets/common.dart';
import 'code_editor.dart';
import 'editor_tools.dart';
import 'insights_panel.dart';
import 'quick_actions.dart';
import 'suggestion_popup.dart';
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
  bool _toolsOpen = true;
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

  // brain
  List<BrainHit> _predictions = const [];
  List<BlockHint>? _blockHints;
  String _hintSig = '';
  Timer? _hintTimer;
  bool _popupShown = false;
  bool _noSuggestOnce = false;
  bool _kbWasOpen = false;
  String? _popupHint;

  @override
  void initState() {
    super.initState();
    _vault = ref.read(vaultProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _body.addListener(_onBodyChanged);
    _focus.addListener(_onFocusChanged);
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
    _hintTimer?.cancel();
    _focus.removeListener(_onFocusChanged);
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
    _noSuggestOnce = true;
    _body.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    _markDirty();
  }

  @override
  void insertAtCursor(String t) {
    _noSuggestOnce = true;
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
    _predictions = const [];
    _popupShown = false;
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
      // Typing opens suggestions — but not when the change came from accepting one, or from a tool button.
      if (_noSuggestOnce) {
        _noSuggestOnce = false;
        _dismissPopup();
      } else {
        _scheduleSuggestions();
      }
    } else {
      // Only the caret moved (a tap in the text, a drag): like a click in the web editor, close the popup.
      _dismissPopup();
      _scheduleSuggestions(popup: false);
    }
    _scheduleLiveScore();
    _scheduleHints();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
    if (!_focus.hasFocus) {
      _dismissPopup();
      return;
    }
    _scheduleSuggestions(popup: false); // refresh the prediction strip only; never pop a list up just for a tap
  }

  /// Closes the suggestion list (and the prediction strip's popup state) without touching the text.
  void _dismissPopup() {
    _suggestTimer?.cancel();
    _popupShown = false;
    if (!mounted) return;
    if (_suggestions.isNotEmpty || _popupHint != null) {
      setState(() {
        _suggestions = const [];
        _popupHint = null;
      });
    }
  }

  /// The keyboard closing (back button, swipe down) must also close the list: it belongs to typing.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final open = views.isNotEmpty && views.first.viewInsets.bottom > 0;
    if (_kbWasOpen && !open) _dismissPopup();
    _kbWasOpen = open;
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

  void _scheduleSuggestions({bool popup = true}) {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 120), () => _computeSuggestions(popup: popup));
  }

  /// The "Suggest" button (Ctrl+Space in the web editor): open suggestions for the caret right now.
  void _suggestNow() {
    _focus.requestFocus();
    _computeSuggestions(force: true);
  }

  void _computeSuggestions({bool popup = true, bool force = false}) {
    if (!mounted) return;
    void clear() {
      _popupShown = false;
      if (_suggestions.isNotEmpty || _predictions.isNotEmpty || _popupHint != null) {
        setState(() {
          _suggestions = const [];
          _predictions = const [];
          _popupHint = null;
        });
      }
    }

    if (!force && !ref.read(deviceSettingsProvider).suggestionsEnabled) {
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
    final trig = popup ? TriggerDetector.detect(before) : null;
    if (trig != null) {
      final kind = TriggerDetector.kindForPrefix(trig.prefix);
      if (kind != null) {
        final items = TriggerDetector.candidatesFor(kind, trig.query, state.data);
        _sugReplaceStart = cursor - trig.fullMatch.length;
        _sugReplaceEnd = cursor;
        _sugSuffix = '';
        _popupShown = false;
        // Like the web editor: a bare prefix with nothing behind it still answers, with a hint.
        final hint = items.isEmpty && trig.query.isEmpty
            ? const {
                'snippet': 'No snippets yet — create one under Templates → Snippets.',
                'prompt': 'No saved prompts yet — save one and it appears here.',
                'pattern': 'No patterns to insert.',
                'template': 'No templates yet — create one under Templates.',
                'block': 'No prompt blocks available.',
                'link': 'No other prompts to link to yet.',
              }[kind]
            : null;
        setState(() {
          _suggestions = items;
          _popupHint = hint;
          _predictions = const [];
        });
        return;
      }
    }
    // 2) variable names inside {{ }}
    final vm = RegExp(r'\{\{\s*([a-zA-Z0-9_]*)$').firstMatch(before);
    final hub = ref.read(suggestionHubProvider);
    final engine = hub.fresh(state);
    if (vm != null && popup) {
      final partial = vm.group(1) ?? '';
      final items = engine.variableSuggestions(partial);
      _sugReplaceStart = cursor - partial.length;
      _sugReplaceEnd = cursor;
      _sugSuffix = after.startsWith('}}') ? '' : '}}';
      _popupShown = false;
      setState(() {
        _suggestions = items;
        _predictions = const [];
      });
      return;
    }
    // 3) the brain: word / phrase completion while typing, next-word predictions after a space
    final bs = ref.read(brainProvider);
    final model = bs.model;
    if (model != null) {
      _sugSuffix = '';
      if (RegExp(r"[A-Za-z][A-Za-z0-9_'’-]*$").hasMatch(before)) {
        if (!popup) return clear();
        final hits = model.complete(before, usage: bs.usage, limit: 8);
        if (hits.isEmpty) return clear();
        _sugReplaceStart = cursor - hits.first.matchLen;
        _sugReplaceEnd = cursor;
        if (!_popupShown) {
          _popupShown = true;
          ref.read(brainProvider.notifier).noteShown();
        }
        setState(() {
          _suggestions = [for (final h in hits) SuggestionItem(h.label, h.insert, h.kind, matchLen: h.matchLen)];
          _predictions = const [];
        });
        return;
      }
      final atBoundary = before.isEmpty || RegExp(r'\s$').hasMatch(before);
      final preds = atBoundary ? model.predictNext(before, usage: bs.usage, limit: force ? 8 : 4) : const <BrainHit>[];
      if (force && preds.isNotEmpty) {
        // asked for explicitly: show the predictions as a list under the caret too
        _sugReplaceStart = cursor;
        _sugReplaceEnd = cursor;
        setState(() {
          _suggestions = [for (final h in preds) SuggestionItem(h.label, h.insert, 'phrase', matchLen: 0)];
          _predictions = const [];
        });
        return;
      }
      _popupShown = false;
      if (_suggestions.isNotEmpty || _popupHint != null || _predictions.length != preds.length || (preds.isNotEmpty && _predictions.isNotEmpty && _predictions.first.insert != preds.first.insert) || (_predictions.isEmpty && preds.isNotEmpty)) {
        setState(() {
          _suggestions = const [];
          _popupHint = null;
          _predictions = preds;
        });
      }
      return;
    }
    // 4) fallback while the brain is still learning: learned phrase / word completion
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
    _noSuggestOnce = true;
    _body.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: replaceStart + ins.length));
    _popupShown = false;
    setState(() => _suggestions = const []);
    if (s.src == 'word' || s.src == 'phrase') ref.read(brainProvider.notifier).recordAccept(s.text);
    if (s.src == 'snippet' && s.meta != null) {
      final sn = ref.read(vaultProvider).data.snippets[s.meta];
      if (sn != null) unawaited(_vault.saveSnippet(sn.clone()..useCount += 1));
    }
  }

  /// Inserts a next-word prediction from the strip above the keyboard.
  void _acceptHit(BrainHit h) {
    final t = _body.text;
    final sel = _body.selection;
    final cur = (sel.isValid ? sel.baseOffset : t.length).clamp(0, t.length);
    final next = t.replaceRange(cur, cur, h.insert);
    _noSuggestOnce = true;
    _body.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: cur + h.insert.length));
    ref.read(brainProvider.notifier).recordAccept(h.insert);
    _focus.requestFocus();
  }

  /// Re-ranks the section chips by what this user usually writes (debounced; the order should not jump while typing).
  void _scheduleHints({bool immediate = false}) {
    _hintTimer?.cancel();
    _hintTimer = Timer(Duration(milliseconds: immediate ? 0 : 1100), () {
      if (!mounted) return;
      final model = ref.read(brainProvider).model;
      if (model == null) return;
      final hints = model.rankBlocks(_body.text);
      final sig = hints.map((h) => '${h.id}${h.present ? 1 : 0}${h.recommended ? 1 : 0}').join();
      if (sig != _hintSig) {
        setState(() {
          _hintSig = sig;
          _blockHints = hints;
        });
      }
    });
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

  static String _clock(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<EditorRequest?>(editorRequestProvider, (_, next) {
      if (next != null) unawaited(_handleRequest(next));
    });
    ref.listen<VaultState>(vaultProvider, _onVaultChanged);
    ref.listen<BrainState>(brainProvider, (prev, next) {
      final up = next.levelUp;
      if (up != null) {
        toast(context, 'Your editor brain reached level $up · ${next.model?.level.name ?? ''}');
        ref.read(brainProvider.notifier).clearLevelUp();
      }
      if (prev?.version != next.version) {
        _scheduleHints(immediate: true);
        _scheduleSuggestions();
      }
    });

    final p = context.pf;
    final ds = ref.watch(deviceSettingsProvider);
    final zen = ref.watch(zenModeProvider);
    final vault = ref.watch(vaultProvider);
    final brain = ref.watch(brainProvider);
    final stored = _prompt == null ? null : vault.data.prompts[_prompt!.id];
    final family = (kEditorFontFallbacks[ds.editorFont] ?? kMonoFallback);
    _body.configure(format: _format, highlight: ds.highlight, colors: p.brightness == Brightness.dark ? const HighlightColors.dark() : const HighlightColors.light());
    final fmtLabel = kPromptFormats.firstWhere((f) => f.id == _format, orElse: () => kPromptFormats.first).label;
    final kbOpen = View.of(context).viewInsets.bottom > 0;
    MediaQuery.of(context); // rebuild when the keyboard opens/closes
    // While typing with the keyboard up, only the action rail stays: the text gets the room.
    final compact = kbOpen && _focus.hasFocus && !zen;
    final showTools = !zen && !compact && _toolsOpen;

    return PopScope(
      canPop: !zen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && zen) ref.read(zenModeProvider.notifier).state = false;
      },
      child: Scaffold(
        backgroundColor: p.editorBg,
        body: SafeArea(
          top: zen,
          child: Stack(children: [
            Positioned.fill(
              child: Column(children: [
                if (!zen && !compact) _header(p, fmtLabel, stored),
                if (!zen && !compact) _subHeader(p, stored),
                if (!zen) _rail(p, brain, stored),
                if (showTools) ...[
                  EditorQuickTools(host: this),
                  EditorBlocksRow(host: this, hints: _blockHints),
                ],
                if (_saveError != null)
                  MaterialBanner(
                    backgroundColor: p.red.withValues(alpha: 0.12),
                    content: Text('Could not save to your folder: $_saveError', style: const TextStyle(fontSize: 13)),
                    actions: [
                      TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: _body.text)), child: const Text('Copy text')),
                      TextButton(onPressed: () => unawaited(_persist()), child: const Text('Retry')),
                    ],
                  ),
                if (_conflict != null)
                  MaterialBanner(
                    backgroundColor: p.amber.withValues(alpha: 0.12),
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
                Expanded(flex: 5, child: _editorCard(p, ds, family, zen, stored)),
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
                if (!zen) _dock(p),
              ]),
            ),
            if (zen) Positioned(top: 8, right: 10, child: RailButton(icon: Icons.fullscreen_exit, tooltip: 'Exit Zen mode', color: p.textSecondary, onTap: () => _menu('zen'))),
          ]),
        ),
      ),
    );
  }

  // ---- header: title, format, overflow menu

  Widget _header(PfPalette p, String fmtLabel, Prompt? stored) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _title,
            onChanged: (_) => _markDirty(),
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            decoration: const InputDecoration(hintText: 'Untitled prompt', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickFormat,
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 11, right: 5),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(fmtLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textSecondary)),
                Icon(Icons.keyboard_arrow_down, size: 18, color: p.textTertiary),
              ]),
            ),
          ),
        ),
        _moreMenu(stored),
      ]),
    );
  }

  Widget _moreMenu(Prompt? stored) => PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: _menu,
        icon: const Icon(Icons.more_vert, size: 22),
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
      );

  // ---- sub header: category / status / tags + save state

  Widget _subHeader(PfPalette p, Prompt? stored) {
    final cat = categoryById(_category);
    final status = statusById(_status);
    return SizedBox(
      height: 36,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 12, 4), children: [
        _miniChip(cat.label, pfColor(cat.color), _pickCategory, dot: true),
        _miniChip(status.label, pfColor(status.color), _pickStatus, dot: true),
        _miniChip(_tags.isEmpty ? 'Add tags' : _tags.map((t) => '#$t').join(' '), p.textSecondary, _editTags, icon: Icons.sell_outlined),
      ]),
    );
  }

  Widget _miniChip(String label, Color color, VoidCallback onTap, {bool dot = false, IconData? icon}) {
    final p = context.pf;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.35))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (dot) Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              if (icon != null) Padding(padding: const EdgeInsets.only(right: 5), child: Icon(icon, size: 13, color: p.textTertiary)),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dot ? color : p.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- action rail

  Widget _rail(PfPalette p, BrainState brain, Prompt? stored) {
    final IconData saveIcon;
    final Color saveColor;
    final String saveTip;
    if (_saveError != null) {
      saveIcon = Icons.error_outline;
      saveColor = p.red;
      saveTip = 'Save failed — tap to retry';
    } else if (_saving || _dirty) {
      saveIcon = Icons.sync;
      saveColor = p.amber;
      saveTip = 'Saving… tap to save now';
    } else if (stored != null) {
      saveIcon = Icons.check_circle_outline;
      saveColor = p.green;
      saveTip = 'Saved to your folder';
    } else {
      saveIcon = Icons.save_outlined;
      saveColor = p.textSecondary;
      saveTip = 'Save';
    }
    final level = brain.model?.level.level;
    return EditorActionRail(children: [
      RailButton(icon: saveIcon, tooltip: saveTip, color: saveColor, onTap: () => unawaited(_persist())),
      RailButton(icon: Icons.history_toggle_off, tooltip: 'Save version', onTap: () => _menu('version')),
      const RailDivider(),
      ValueListenableBuilder<UndoHistoryValue>(
        valueListenable: _undo,
        builder: (context, v, _) => Row(children: [
          RailButton(icon: Icons.undo, tooltip: 'Undo', onTap: v.canUndo ? _undo.undo : null),
          RailButton(icon: Icons.redo, tooltip: 'Redo', onTap: v.canRedo ? _undo.redo : null),
        ]),
      ),
      RailButton(icon: Icons.search, tooltip: 'Find & replace', active: _findOpen, onTap: () => _menu('find')),
      const RailDivider(),
      RailButton(icon: Icons.insights_outlined, tooltip: 'DNA & analyzer', active: _insights, onTap: () => setState(() => _insights = !_insights)),
      RailButton(icon: Icons.fullscreen, tooltip: 'Zen mode', onTap: () => _menu('zen')),
      const RailDivider(),
      _BrainPill(level: level, building: brain.building, onTap: () => unawaited(showBrainSheet(context))),
      const SizedBox(width: 8),
      Center(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('Tools'),
          onPressed: () async {
            FocusScope.of(context).unfocus();
            await showEditorTools(context, this);
          },
        ),
      ),
      const RailDivider(),
      RailButton(icon: Icons.copy, tooltip: 'Copy text', onTap: _copyText),
      RailButton(icon: Icons.file_download_outlined, tooltip: 'Download / export', onTap: () => _menu('export')),
      RailButton(icon: Icons.add, tooltip: 'New prompt', onTap: () => _menu('new')),
      RailButton(icon: _toolsOpen ? Icons.expand_less : Icons.expand_more, tooltip: _toolsOpen ? 'Hide tool rows' : 'Show tool rows', onTap: () => setState(() => _toolsOpen = !_toolsOpen)),
    ]);
  }

  // ---- the editor card

  Widget _editorCard(PfPalette p, DeviceSettings ds, List<String> family, bool zen, Prompt? stored) {
    final focused = _focus.hasFocus;
    final editor = CodeEditor(
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
      popup: _suggestions.isNotEmpty || _popupHint != null ? SuggestionPopup(items: _suggestions, hint: _popupHint, onPick: _acceptSuggestion) : null,
      popupHeight: _suggestions.isEmpty ? SuggestionPopup.hintHeight : SuggestionPopup.heightFor(_suggestions.length),
      popupWidth: _suggestions.isEmpty ? 270 : SuggestionPopup.widthFor(_suggestions, 300),
      scrollController: _scroll,
      hint: 'Write your prompt…  Try / for snippets, // for prompts, @ for links, {{ for variables.',
    );
    if (zen) return editor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: p.editorBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: focused ? p.blue.withValues(alpha: 0.7) : p.border),
          boxShadow: focused ? [BoxShadow(color: p.blue.withValues(alpha: 0.16), blurRadius: 16, spreadRadius: 0.5)] : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Expanded(child: editor),
          _cardFooter(p, ds, stored),
        ]),
      ),
    );
  }

  Widget _cardFooter(PfPalette p, DeviceSettings ds, Prompt? stored) {
    final d = ref.watch(vaultProvider).data;
    ref.watch(tokenizerProvider);
    final String saveText;
    final Color saveColor;
    if (_saveError != null) {
      saveText = 'Save failed';
      saveColor = p.red;
    } else if (_saving || _dirty) {
      saveText = 'Saving…';
      saveColor = p.amber;
    } else if (stored != null) {
      saveText = 'Saved · ${_clock(stored.updatedAt)}';
      saveColor = p.green;
    } else {
      saveText = 'Not saved yet';
      saveColor = p.textTertiary;
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _body,
      builder: (context, v, _) {
        final words = Utils.countWords(v.text);
        final model = d.settings.selectedModel;
        final custom = d.settings.customModels;
        final tok = TokenEstimator.estimateTokens(v.text, model, custom);
        final ctx = TokenEstimator.contextStatus(v.text, model, custom);
        final exact = TokenEstimator.isExact(model, custom);
        final modelLabel = TokenEstimator.getModel(model, custom).label;
        final overWords = ds.wordCountWarning > 0 && words > ds.wordCountWarning;
        final statColor = ctx.level == 'over' ? p.red : (overWords || ctx.level == 'warn' ? p.amber : p.textTertiary);
        final barColor = ctx.level == 'over' ? p.red : (ctx.level == 'warn' ? p.amber : p.blue);
        return Container(
          decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.55), border: Border(top: BorderSide(color: p.borderSubtle))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
              child: SizedBox(
                height: 34,
                child: Row(children: [
                  Text(saveText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: saveColor)),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Text('·', style: TextStyle(color: p.textTertiary))),
                  Expanded(
                    child: Text(
                      overWords ? '$words words — over your ${ds.wordCountWarning}-word limit · ${exact ? '' : '~'}$tok tok' : '$words words · ${exact ? '' : '~'}$tok tok ($modelLabel)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: statColor, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback),
                    ),
                  ),
                  if (_liveScore != null)
                    Tooltip(
                      message: 'Live analyzer score',
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: scoreColor(context, _liveScore!).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                        child: Text('$_liveScore', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: scoreColor(context, _liveScore!))),
                      ),
                    ),
                ]),
              ),
            ),
            SizedBox(height: 2, child: LinearProgressIndicator(value: (ctx.pct / 100).clamp(0.0, 1.0).toDouble(), minHeight: 2, color: barColor, backgroundColor: Colors.transparent)),
          ]),
        );
      },
    );
  }

  // ---- bottom dock: brain predictions + typing triggers

  Widget _dock(PfPalette p) {
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_predictions.isNotEmpty && _focus.hasFocus) BrainStrip(hits: _predictions, onPick: _acceptHit),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 7, bottom: 7),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.auto_awesome, size: 15, color: p.amber),
                  label: const Text('Suggest', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: _suggestNow,
                ),
              ),
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
                  padding: const EdgeInsets.only(right: 6, top: 7, bottom: 7),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${t[0]} ${t[1]}', style: TextStyle(fontSize: 12, fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback)),
                    onPressed: () {
                      if (t[0] == '{{}}') {
                        insertAtCursor('{{}}');
                        final off = _body.selection.baseOffset - 2;
                        _body.selection = TextSelection.collapsed(offset: off);
                        _focus.requestFocus();
                        _scheduleSuggestions(); // offer the known variable names right away
                      } else {
                        _quickInsert(t[0]);
                      }
                    },
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

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
}

/// The little brain button on the action rail: shows the brain level and opens the brain dashboard.
class _BrainPill extends StatelessWidget {
  final int? level;
  final bool building;
  final VoidCallback onTap;
  const _BrainPill({required this.level, required this.building, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Center(
      child: Tooltip(
        message: 'Editor brain',
        child: Material(
          color: p.violet.withValues(alpha: 0.14),
          shape: StadiumBorder(side: BorderSide(color: p.violet.withValues(alpha: 0.45))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (building) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.violet)) else Icon(Icons.psychology, size: 17, color: p.violet),
                const SizedBox(width: 5),
                Text(level == null ? 'Brain' : 'Lv $level', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.violet)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
