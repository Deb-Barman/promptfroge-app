import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell.dart';
import '../../core/date_parse.dart';
import '../../core/util.dart';
import '../../state/vault_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/pf_chrome.dart';
import '../widgets/common.dart';
import '../widgets/fill_variables.dart';

enum _Kind { prompts, templates, patterns, chains, history }

const Map<_Kind, String> _kindLabel = {
  _Kind.prompts: 'Prompts',
  _Kind.templates: 'Templates',
  _Kind.patterns: 'Patterns (custom)',
  _Kind.chains: 'Chains',
  _Kind.history: 'Saved versions',
};

class _Hit {
  final _Kind kind;
  final String id;
  final String? promptId;
  final String title;
  final int ts;
  final int size;
  const _Hit(this.kind, this.id, this.title, this.ts, this.size, {this.promptId});
}

/// "Search by date": everything you created or changed on one day or across a range, across all content types.
class DateSearchScreen extends ConsumerStatefulWidget {
  const DateSearchScreen({super.key});

  @override
  ConsumerState<DateSearchScreen> createState() => _DateSearchScreenState();
}

class _DateSearchScreenState extends ConsumerState<DateSearchScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _range = false;
  String _sort = 'newest';
  final Set<_Kind> _types = {..._Kind.values};
  String? _error;
  List<_Hit>? _hits;
  bool _busy = false;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: parseFlexibleDate(c.text) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null) {
      c.text = dateToFlexibleText(d);
      _search();
    }
  }

  Future<void> _search() async {
    final d = ref.read(vaultProvider).data;
    final fromDate = parseFlexibleDate(_from.text);
    final toDate = _range ? parseFlexibleDate(_to.text) : fromDate;
    if (fromDate == null) {
      setState(() {
        _error = 'Enter or pick a valid date first.';
        _hits = null;
      });
      return;
    }
    final start = DateTime(fromDate.year, fromDate.month, fromDate.day).millisecondsSinceEpoch;
    final td = toDate ?? fromDate;
    final end = DateTime(td.year, td.month, td.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    if (end < start) {
      setState(() {
        _error = 'The second date is before the first — swap them?';
        _hits = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    bool inRange(int ts) => ts >= start && ts <= end;
    final items = <_Hit>[];
    if (_types.contains(_Kind.prompts)) {
      for (final p in d.prompts.values) {
        if (inRange(p.updatedAt)) items.add(_Hit(_Kind.prompts, p.id, p.displayTitle, p.updatedAt, p.body.length));
      }
    }
    if (_types.contains(_Kind.templates)) {
      for (final t in d.templates.values) {
        if (inRange(t.updatedAt)) items.add(_Hit(_Kind.templates, t.id, t.displayName, t.updatedAt, t.body.length));
      }
    }
    if (_types.contains(_Kind.patterns)) {
      for (final x in d.customPatterns.values) {
        if (inRange(x.updatedAt)) items.add(_Hit(_Kind.patterns, x.id, x.name.isEmpty ? 'Untitled pattern' : x.name, x.updatedAt, x.template.length));
      }
    }
    if (_types.contains(_Kind.chains)) {
      for (final c in d.chains.values) {
        if (inRange(c.updatedAt)) items.add(_Hit(_Kind.chains, c.id, c.name.isEmpty ? 'Untitled chain' : c.name, c.updatedAt, c.steps.length));
      }
    }
    if (_types.contains(_Kind.history)) {
      final all = await ref.read(vaultProvider.notifier).allVersions();
      for (final list in all.values) {
        for (final v in list) {
          if (inRange(v.createdAt)) {
            items.add(_Hit(_Kind.history, v.id, '${v.title.isEmpty ? 'Untitled' : v.title} — v${v.versionNum}', v.createdAt, v.body.length, promptId: v.promptId));
          }
        }
      }
    }
    int cmp(_Hit a, _Hit b) {
      switch (_sort) {
        case 'oldest':
          return a.ts.compareTo(b.ts);
        case 'az':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'za':
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case 'big':
          return b.size.compareTo(a.size);
        case 'small':
          return a.size.compareTo(b.size);
        default:
          return b.ts.compareTo(a.ts);
      }
    }

    items.sort(cmp);
    if (!mounted) return;
    setState(() {
      _hits = items;
      _busy = false;
    });
  }

  Future<void> _open(_Hit h) async {
    final d = ref.read(vaultProvider).data;
    switch (h.kind) {
      case _Kind.prompts:
        openInEditor(context, ref, promptId: h.id);
      case _Kind.history:
        if (h.promptId != null && d.prompts.containsKey(h.promptId)) context.push('/history?id=${h.promptId}');
      case _Kind.templates:
        final t = d.templates[h.id];
        if (t == null) return;
        final text = await fillVariables(context, t.body, title: t.displayName, actionLabel: 'Open in editor');
        if (text == null || !mounted) return;
        await ref.read(vaultProvider.notifier).incrementTemplateUse(t.id);
        if (mounted) openInEditor(context, ref, seedBody: text, seedTitle: t.displayName);
      case _Kind.patterns:
        context.push('/patterns');
      case _Kind.chains:
        context.push('/chains');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final hits = _hits;
    return Scaffold(
      appBar: PfAppBar(title: const Text('Search by date')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('On a date')), ButtonSegment(value: true, label: Text('Date range'))],
          selected: {_range},
          onSelectionChanged: (s) => setState(() => _range = s.first),
        ),
        const SizedBox(height: 12),
        _dateField(_range ? 'From' : 'Date', _from, 'Today, 12 September 2026, 12/9/2026…'),
        if (_range) ...[const SizedBox(height: 10), _dateField('To', _to, 'e.g. 3 September 2026')],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in _Kind.values)
            FilterChip(
              label: Text(_kindLabel[k]!),
              selected: _types.contains(k),
              onSelected: (v) => setState(() => v ? _types.add(k) : _types.remove(k)),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text('Sort', style: TextStyle(color: p.textTertiary, fontSize: 13)),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _sort,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'newest', child: Text('Newest first')),
              DropdownMenuItem(value: 'oldest', child: Text('Oldest first')),
              DropdownMenuItem(value: 'az', child: Text('Title A–Z')),
              DropdownMenuItem(value: 'za', child: Text('Title Z–A')),
              DropdownMenuItem(value: 'big', child: Text('Largest first')),
              DropdownMenuItem(value: 'small', child: Text('Smallest first')),
            ],
            onChanged: (v) {
              setState(() => _sort = v ?? 'newest');
              if (_hits != null) _search();
            },
          ),
          const Spacer(),
          FilledButton.icon(icon: const Icon(Icons.search, size: 18), label: const Text('Search'), onPressed: _busy ? null : _search),
        ]),
        const SizedBox(height: 12),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 20), child: Center(child: Text(_error!, style: TextStyle(color: p.amber)))),
        if (hits != null && hits.isEmpty)
          const EmptyState(icon: Icons.event_busy, title: 'No matches', body: 'Nothing was created or changed in that period for the selected types.'),
        if (hits != null && hits.isNotEmpty) ...[
          Text('${hits.length} result${hits.length == 1 ? '' : 's'}', style: TextStyle(color: p.textTertiary, fontSize: 12)),
          const SizedBox(height: 8),
          for (final h in hits)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: PfCard(
                onTap: () => _open(h),
                child: Row(children: [
                  StatusBadge(_kindLabel[h.kind]!.toUpperCase(), p.blue),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                  const SizedBox(width: 8),
                  Text(Utils.timeAgo(h.ts), style: TextStyle(color: p.textTertiary, fontSize: 11.5)),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _dateField(String label, TextEditingController c, String hint) => TextField(
        controller: c,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: IconButton(tooltip: 'Pick a date', icon: const Icon(Icons.calendar_month_outlined), onPressed: () => _pick(c)),
        ),
      );
}
