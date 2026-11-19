import 'dart:convert';

import '../../core/constants.dart';
import '../../core/util.dart';
import 'engine_util.dart';
import 'format_converter.dart';
import 'template_engine.dart';

class AmbiguityFinding {
  final String sentence;
  final int index;
  const AmbiguityFinding(this.sentence, this.index);
}

class AdversarialFinding {
  final String id;
  final String label;
  const AdversarialFinding(this.id, this.label);
}

class RedundancyFinding {
  final String a;
  final String b;
  const RedundancyFinding(this.a, this.b);
}

class InjectionFinding {
  final String id;
  final String label;
  final String detail;
  const InjectionFinding(this.id, this.label, this.detail);
}

class _Rule {
  final RegExp re;
  final String to;
  _Rule(String pattern, this.to) : re = RegExp(pattern, caseSensitive: false);
}

/// Rule-based editor transforms and checks (no model calls).
class PromptTools {
  PromptTools._();

  static final List<RegExp> _filler = <String>[
    r'\bplease (?:make sure to|be sure to|kindly)\b',
    r'\bit is important to (?:note that|remember that)\b',
    r'\bplease note that\b',
    r'\bkeep in mind that\b',
    r'\bas (?:previously|already) (?:mentioned|stated|noted)\b',
    r'\bfor your information\b',
    r'\bat this point in time\b',
    r'\bwith regard to\b',
    r'\bin terms of\b',
    r'\bbasically\b',
    r'\bactually\b',
    r'\bjust\b(?=\s)',
    r'\bvery\b(?=\s)',
    r'\breally\b(?=\s)',
    r'\bsimply\b(?=\s)',
  ].map((p) => RegExp(p, caseSensitive: false)).toList();

  static final RegExp _sentenceStart = RegExp(r'(^|[.!?]\s+)([a-z])');

  static String _recapitalize(String s) => s.replaceAllMapped(_sentenceStart, (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}');

  static String shorten(String? text) {
    var out = text ?? '';
    out = out
        .replaceAll(RegExp(r'\bin order to\b', caseSensitive: false), 'to')
        .replaceAll(RegExp(r'\bdue to the fact that\b', caseSensitive: false), 'because')
        .replaceAll(RegExp(r'\bin the event that\b', caseSensitive: false), 'if');
    for (final re in _filler) {
      out = out.replaceAll(re, '');
    }
    out = out
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return _recapitalize(out);
  }

  static final RegExp _listItem = RegExp(r'^(?:[-*•]|\d+[.)])\s');

  static String bulletify(String? text) {
    final lines = (text ?? '').split('\n');
    final out = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _listItem.hasMatch(trimmed) || trimmed.endsWith(':')) {
        out.add(line);
        continue;
      }
      final sentences = Utils.splitSentences(trimmed);
      if (sentences.length >= 2) {
        for (final s in sentences) {
          out.add('- ${s.trim()}');
        }
      } else {
        out.add(line);
      }
    }
    return out.join('\n');
  }

  static String chainOfThoughtBlock() =>
      '\n\nBefore giving your final answer, think through the problem step by step. Show your reasoning, then clearly mark your final answer (e.g. with "Final answer:").';

  static String? tableify(String? text) {
    final items = (text ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => _listItem.hasMatch(l))
        .map((l) => l.replaceFirst(_listItem, ''))
        .toList();
    if (items.length < 2) return null;
    if (items.every((i) => i.contains(':'))) {
      final rows = items.map((i) {
        final idx = i.indexOf(':');
        return '| ${i.substring(0, idx).trim()} | ${i.substring(idx + 1).trim()} |';
      }).join('\n');
      return '| Item | Detail |\n|---|---|\n$rows';
    }
    return '| Item |\n|---|\n${items.map((i) => '| $i |').join('\n')}';
  }

  static const List<String> tones = ['formal', 'casual', 'persuasive', 'neutral'];

  static final Map<String, List<_Rule>> _toneMaps = {
    'formal': [
      _Rule(r"\bcan't\b", 'cannot'),
      _Rule(r"\bdon't\b", 'do not'),
      _Rule(r"\bwon't\b", 'will not'),
      _Rule(r"\bit's\b", 'it is'),
      _Rule(r"\byou're\b", 'you are'),
      _Rule(r"\bwe're\b", 'we are'),
      _Rule(r"\bI'm\b", 'I am'),
      _Rule(r'\bgonna\b', 'going to'),
      _Rule(r'\bkind of\b', 'somewhat'),
      _Rule(r'\ba lot of\b', 'a substantial amount of'),
      _Rule(r'\bstart\b', 'commence'),
    ],
    'casual': [
      _Rule(r'\bcannot\b', "can't"),
      _Rule(r'\bdo not\b', "don't"),
      _Rule(r'\bwill not\b', "won't"),
      _Rule(r'\bit is\b', "it's"),
      _Rule(r'\butilize\b', 'use'),
      _Rule(r'\bapproximately\b', 'about'),
      _Rule(r'\badditional\b', 'more'),
      _Rule(r'\bpurchase\b', 'buy'),
    ],
    'persuasive': [
      _Rule(r'\bcan\b', 'can absolutely'),
      _Rule(r'\bgood\b', 'outstanding'),
      _Rule(r'\bwill\b', 'will definitely'),
      _Rule(r'\bimportant\b', 'essential'),
      _Rule(r'\bshould\b', 'need to'),
    ],
    'neutral': [
      _Rule(r'\bawesome\b', 'good'),
      _Rule(r'\bamazing\b', 'notable'),
      _Rule(r'\bcan absolutely\b', 'can'),
      _Rule(r'\bwill definitely\b', 'will'),
      _Rule(r'\bdefinitely\b', ''),
      _Rule(r'\bobviously\b', ''),
      _Rule(r'\bclearly\b', ''),
    ],
  };

  static String toneShift(String? text, String tone) {
    var out = text ?? '';
    for (final r in _toneMaps[tone] ?? const <_Rule>[]) {
      out = out.replaceAll(r.re, r.to);
    }
    out = out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m.group(1)!).trim();
    return _recapitalize(out);
  }

  static List<AmbiguityFinding> scanAmbiguity(String? text) {
    final sentences = Utils.splitSentences(text);
    final re = RegExp(r'^(?:it|this|that|these|those|they)\b', caseSensitive: false);
    final out = <AmbiguityFinding>[];
    for (var i = 0; i < sentences.length; i++) {
      final t = sentences[i].trim();
      if (re.hasMatch(t)) out.add(AmbiguityFinding(t.length > 80 ? t.substring(0, 80) : t, i));
    }
    return out;
  }

  static final List<_AdvPattern> _adversarial = [
    _AdvPattern('ignore_prev', RegExp(r'\bignore (?:all |any )?(?:previous|prior|above) instructions?\b', caseSensitive: false), '"Ignore previous instructions" phrasing'),
    _AdvPattern('pretend_no_rules', RegExp(r'\bpretend (?:you have no|there are no) (?:rules|restrictions|guidelines)\b', caseSensitive: false), '"Pretend you have no rules" phrasing'),
    _AdvPattern('dan_style', RegExp(r'\bdo anything now\b|\bDAN mode\b', caseSensitive: false), '"Do Anything Now" / DAN-style jailbreak phrasing'),
    _AdvPattern('reveal_system', RegExp(r'\breveal (?:your |the )?(?:system prompt|hidden instructions|initial prompt)\b', caseSensitive: false), 'Request to reveal system/hidden prompt'),
    _AdvPattern('hide_ai', RegExp(r"\b(?:don'?t|never) (?:mention|reveal|disclose) (?:that )?you'?re (?:an? )?(?:ai|language model|bot)\b", caseSensitive: false), 'Instruction to hide AI disclosure'),
    _AdvPattern('roleplay_unrestricted', RegExp(r'\bunrestricted (?:mode|version|ai)\b', caseSensitive: false), '"Unrestricted mode" framing'),
  ];

  static List<AdversarialFinding> scanAdversarial(String? text) {
    final raw = text ?? '';
    return [
      for (final p in _adversarial)
        if (p.re.hasMatch(raw)) AdversarialFinding(p.id, p.label)
    ];
  }

  static List<RedundancyFinding> findInternalRedundancy(String? text) {
    final sentences = Utils.splitSentences(text).map((s) => s.trim()).where((s) => s.length > 8).toList();
    final findings = <RedundancyFinding>[];
    final seen = <_Seen>[];
    final nonAlnum = RegExp(r'[^a-z0-9\s]');
    for (final s in sentences) {
      final norm = s.toLowerCase().replaceAll(nonAlnum, '').trim();
      _Seen? dup;
      for (final prior in seen) {
        final maxLen = prior.norm.length > norm.length ? prior.norm.length : norm.length;
        if ((prior.norm.length - norm.length).abs() > maxLen * 0.3) continue;
        final a = prior.norm.split(RegExp(r'\s+')).toSet();
        final b = norm.split(RegExp(r'\s+')).toSet();
        final overlap = a.where(b.contains).length;
        var denom = a.length > b.length ? a.length : b.length;
        if (denom < 1) denom = 1;
        if (overlap / denom > 0.75) {
          dup = prior;
          break;
        }
      }
      if (dup != null && !findings.any((f) => f.a == dup!.text)) findings.add(RedundancyFinding(dup.text, s));
      seen.add(_Seen(norm, s));
    }
    return findings;
  }

  /// Structural check: prompt references user input but has no delimiter around it.
  static List<InjectionFinding> checkInjectionSurface(String? text) {
    final raw = text ?? '';
    if (raw.trim().isEmpty) return const [];
    final refs = RegExp(r"\b(?:the following (?:text|input|content|message|document)|user'?s? (?:input|message|question|request)|below:?\s*$)", caseSensitive: false, multiLine: true).hasMatch(raw) ||
        RegExp(r'\{\{\s*(?:user_input|input|user_text|user_message|content|text)\s*\}\}', caseSensitive: false).hasMatch(raw);
    if (!refs) return const [];
    final delimited = RegExp(r'<[a-z_]+>[\s\S]*<\/[a-z_]+>', caseSensitive: false).hasMatch(raw) ||
        raw.contains('```') ||
        raw.contains('"""') ||
        RegExp(r'^-{3,}\s*$', multiLine: true).hasMatch(raw);
    if (delimited) return const [];
    return const [
      InjectionFinding('unfenced_user_input', "User input isn't clearly delimited",
          'This prompt appears to reference user-supplied content without a structural boundary (like <user_input>…</user_input>, a fenced ``` block, or a --- separator). Without one, text inside that content could be read as additional instructions rather than data to process.')
    ];
  }
}

class _AdvPattern {
  final String id;
  final RegExp re;
  final String label;
  _AdvPattern(this.id, this.re, this.label);
}

class _Seen {
  final String norm;
  final String text;
  _Seen(this.norm, this.text);
}

/// "Adapt for model" / "Wrap in XML tags" structural transforms.
class ModelAdapter {
  ModelAdapter._();

  static String _tag(String label) {
    final v = label.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return v.isEmpty ? 'section' : v;
  }

  static String _xml(List<Section> sections) => sections.map((s) {
        final tag = _tag(s.label);
        return '<$tag>\n${s.content}\n</$tag>';
      }).join('\n\n');

  static String wrapInXml(String body, [String fromFormat = 'text']) => _xml(FormatConverter.extractSections(body, fromFormat));

  /// [idiomKey]: claude | openai | gemini | generic
  static String adapt(String body, String fromFormat, String idiomKey) {
    final sections = FormatConverter.extractSections(body, fromFormat);
    if (sections.isEmpty) return body;
    if (idiomKey == 'claude') {
      return _xml(_moveEarly(sections, const ['constraints', 'constraint']));
    }
    if (idiomKey == 'openai') {
      final renamed = sections.map((s) => RegExp(r'^role$', caseSensitive: false).hasMatch(s.label.trim()) ? Section('System', s.content) : s).toList();
      return FormatConverter.toMarkdown(renamed);
    }
    if (idiomKey == 'gemini') {
      final hasOutput = sections.any((s) => RegExp('output', caseSensitive: false).hasMatch(s.label));
      final withReminder = hasOutput
          ? sections
          : [...sections, const Section('Output Format', 'Keep the response focused and no longer than necessary for the task.')];
      return FormatConverter.toText(withReminder);
    }
    return FormatConverter.toText(sections);
  }

  static List<Section> _moveEarly(List<Section> sections, List<String> keywords) {
    if (sections.length < 2) return sections;
    bool matches(String l) => keywords.any((k) => l.toLowerCase().contains(k));
    final early = <Section>[];
    final rest = <Section>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0 && matches(sections[i].label)) {
        early.add(sections[i]);
      } else {
        rest.add(sections[i]);
      }
    }
    if (early.isEmpty) return sections;
    return [rest.first, ...early, ...rest.skip(1)];
  }
}

class SystemUser {
  final String system;
  final String user;
  const SystemUser(this.system, this.user);
}

/// Formats a prompt into ready-to-paste snippets (JSON / SDK stubs / cURL / LangChain).
/// Pure string templating - nothing is ever sent anywhere.
class MessageComposer {
  MessageComposer._();

  static List<SimpleOption> formatsFor(String vendor) {
    List<SimpleOption> base;
    switch (vendor) {
      case 'Anthropic':
        base = const [
          SimpleOption('anthropic_json', 'Messages API (JSON)'),
          SimpleOption('python_anthropic', 'Python (anthropic SDK)'),
          SimpleOption('curl', 'cURL'),
        ];
        break;
      case 'OpenAI':
        base = const [
          SimpleOption('openai_json', 'Chat Completions (JSON)'),
          SimpleOption('python_openai', 'Python (openai SDK)'),
          SimpleOption('curl', 'cURL'),
        ];
        break;
      case 'Google':
        base = const [
          SimpleOption('python_gemini', 'Python (google-generativeai)'),
          SimpleOption('openai_json', 'Messages array (JSON)'),
        ];
        break;
      default:
        base = const [SimpleOption('openai_json', 'Messages array (JSON)')];
    }
    return [...base, const SimpleOption('langchain', 'LangChain PromptTemplate')];
  }

  static SystemUser splitSystemUser(String? body) {
    final raw = body ?? '';
    final otherHeaders = kBlockTypes.map((b) => b.label).where((l) => l != 'Role' && l != 'Context').map(RegExp.escape).join('|');
    final m = RegExp('^($otherHeaders)\\s*:', multiLine: true).firstMatch(raw);
    if (m == null || m.start == 0) {
      final roleOnly = RegExp(r'^(?:Role|Context)\s*:[\s\S]*?(?=\n\s*\n|$)', caseSensitive: false).firstMatch(raw);
      if (roleOnly != null && roleOnly.start == 0) {
        final rest = raw.substring(roleOnly.group(0)!.length).trim();
        return SystemUser(roleOnly.group(0)!.trim(), rest.isEmpty ? raw.trim() : rest);
      }
      return SystemUser('', raw.trim());
    }
    return SystemUser(raw.substring(0, m.start).trim(), raw.substring(m.start).trim());
  }

  static List<Map<String, String>> toMessagesArray(String? body) {
    final su = splitSystemUser(body);
    final messages = <Map<String, String>>[];
    if (su.system.isNotEmpty) messages.add({'role': 'system', 'content': su.system});
    messages.add({'role': 'user', 'content': su.user.isNotEmpty ? su.user : (body ?? '')});
    return messages;
  }

  static String _j(String s) => jsonEncode(s);

  static String toOpenAIJson(String? body, String modelId) =>
      jsonStringify({'model': modelId, 'messages': toMessagesArray(body)}, indent: 2);

  static String toAnthropicJson(String? body, String modelId) {
    final su = splitSystemUser(body);
    final payload = <String, Object?>{
      'model': modelId,
      'max_tokens': 1024,
      'messages': [
        {'role': 'user', 'content': su.user.isNotEmpty ? su.user : (body ?? '')}
      ],
    };
    if (su.system.isNotEmpty) payload['system'] = su.system;
    return jsonStringify(payload, indent: 2);
  }

  static String toPythonAnthropic(String? body, String modelId) {
    final su = splitSystemUser(body);
    final sysLine = su.system.isNotEmpty ? '    system=${_j(su.system)},\n' : '';
    return 'import anthropic\n\nclient = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env\n\nresponse = client.messages.create(\n    model=${_j(modelId)},\n    max_tokens=1024,\n$sysLine    messages=[\n        {"role": "user", "content": ${_j(su.user.isNotEmpty ? su.user : (body ?? ''))}}\n    ]\n)\nprint(response.content[0].text)';
  }

  static String toPythonOpenAI(String? body, String modelId) {
    final lines = toMessagesArray(body).map((m) => '        {"role": ${_j(m['role']!)}, "content": ${_j(m['content']!)}}').join(',\n');
    return 'from openai import OpenAI\n\nclient = OpenAI()  # reads OPENAI_API_KEY from env\n\nresponse = client.chat.completions.create(\n    model=${_j(modelId)},\n    messages=[\n$lines\n    ]\n)\nprint(response.choices[0].message.content)';
  }

  static String toCurl(String? body, String modelId, String vendor) {
    if (vendor == 'Anthropic') {
      final json = toAnthropicJson(body, modelId).replaceAll("'", "'\\''");
      return 'curl https://api.anthropic.com/v1/messages \\\n  -H "x-api-key: \$ANTHROPIC_API_KEY" \\\n  -H "anthropic-version: 2023-06-01" \\\n  -H "content-type: application/json" \\\n  -d \'$json\'';
    }
    final json = toOpenAIJson(body, modelId).replaceAll("'", "'\\''");
    return 'curl https://api.openai.com/v1/chat/completions \\\n  -H "Authorization: Bearer \$OPENAI_API_KEY" \\\n  -H "Content-Type: application/json" \\\n  -d \'$json\'';
  }

  static String toLangChain(String? body) {
    final vars = TemplateEngine.extractVariables(body);
    final inputVars = vars.isNotEmpty ? 'input_variables=${jsonEncode(vars)}' : 'input_variables=[]';
    return 'from langchain.prompts import PromptTemplate\n\ntemplate = ${_j(body ?? '')}\n\nprompt = PromptTemplate(\n    $inputVars,\n    template=template\n)';
  }

  static String toGeminiPython(String? body, String modelId) {
    final su = splitSystemUser(body);
    final sysArg = su.system.isNotEmpty ? ', system_instruction=${_j(su.system)}' : '';
    return 'import google.generativeai as genai\n\ngenai.configure(api_key="YOUR_API_KEY")\nmodel = genai.GenerativeModel(${_j(modelId)}$sysArg)\n\nresponse = model.generate_content(${_j(su.user.isNotEmpty ? su.user : (body ?? ''))})\nprint(response.text)';
  }

  static String render(String? body, String format, String modelId, String vendor) {
    switch (format) {
      case 'openai_json':
        return toOpenAIJson(body, modelId);
      case 'anthropic_json':
        return toAnthropicJson(body, modelId);
      case 'python_anthropic':
        return toPythonAnthropic(body, modelId);
      case 'python_openai':
        return toPythonOpenAI(body, modelId);
      case 'python_gemini':
        return toGeminiPython(body, modelId);
      case 'curl':
        return toCurl(body, modelId, vendor);
      case 'langchain':
        return toLangChain(body);
      default:
        return jsonStringify(toMessagesArray(body), indent: 2);
    }
  }
}
