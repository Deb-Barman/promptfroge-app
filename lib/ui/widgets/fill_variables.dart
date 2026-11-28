import 'package:flutter/material.dart';

import '../../domain/engines/template_engine.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'pf_menu.dart';

/// Asks for values of every `{{variable}}` in [body] and returns the rendered text
/// (or null when cancelled). Bodies without variables are returned unchanged immediately.
Future<String?> fillVariables(BuildContext context, String body, {String title = 'Fill variables', String actionLabel = 'Use'}) async {
  final specs = TemplateEngine.extractVariableSpecs(body);
  if (specs.isEmpty) return body;
  return showPfSheet<String>(
    context,
    title: title,
    full: true,
    builder: (ctx) => _FillSheet(body: body, specs: specs, actionLabel: actionLabel),
  );
}

class _FillSheet extends StatefulWidget {
  final String body;
  final List<VarSpec> specs;
  final String actionLabel;
  const _FillSheet({required this.body, required this.specs, required this.actionLabel});

  @override
  State<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<_FillSheet> {
  late final Map<String, String> _values = {for (final s in widget.specs) s.name: s.defaultValue};

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final rendered = TemplateEngine.render(widget.body, _values);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
      for (final s in widget.specs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: s.type == 'select' && s.options.isNotEmpty
              ? PfField<String>(
                  label: TemplateEngine.humanizeVarName(s.name),
                  value: s.options.contains(_values[s.name]) ? _values[s.name] : null,
                  items: [for (final o in s.options) PfMenuItem<String>(o, o)],
                  onChanged: (v) => setState(() => _values[s.name] = v),
                )
              : TextFormField(
                  initialValue: s.defaultValue,
                  keyboardType: s.type == 'number' ? TextInputType.number : TextInputType.multiline,
                  maxLines: s.type == 'multiline' ? 4 : 1,
                  decoration: InputDecoration(labelText: TemplateEngine.humanizeVarName(s.name), hintText: '{{${s.name}}}'),
                  onChanged: (v) => setState(() => _values[s.name] = v),
                ),
        ),
      const SectionTitle('Preview'),
      PfCard(child: SelectableText(rendered, style: TextStyle(fontFamily: kMonoFallback.first, fontFamilyFallback: kMonoFallback, fontSize: 12.5))),
      const SizedBox(height: 12),
      FilledButton(onPressed: () => Navigator.pop(context, rendered), child: Text(widget.actionLabel)),
      if (TemplateEngine.hasUnfilledVariables(rendered))
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Some variables are still empty and will stay as {{placeholders}}.', style: TextStyle(color: p.amber, fontSize: 12.5))),
    ]);
  }
}
