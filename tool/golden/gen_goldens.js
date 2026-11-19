// Generates test/goldens/engines.json by running the ORIGINAL JavaScript from PromptForge.html.
// Usage: node tool/golden/gen_goldens.js path/to/PromptForge.html > test/goldens/engines.json
// The Dart tests under test/engines/ read this file; never edit the output by hand.
const { load, hasDomParser } = require('./load_original');
if (!hasDomParser()) { console.error('Missing dev dependency. Run: npm install --no-save @xmldom/xmldom'); process.exit(1); }
const F = require('./fixtures');
const o = load(process.argv[2]);

// Two original UIManager methods are pure functions of their arguments, so they are lifted out of the HTML source
// and run directly (brace-matched from the method signature) instead of loading the whole DOM-bound class.
const fs = require('fs');
const htmlSrc = fs.readFileSync(process.argv[2], 'utf8');
function liftMethod(name, params) {
  const start = htmlSrc.indexOf(`  ${name}(${params}){`);
  if (start < 0) throw new Error('method not found: ' + name);
  let i = htmlSrc.indexOf('{', start), depth = 0, j = i;
  for (; j < htmlSrc.length; j++) { const c = htmlSrc[j]; if (c === '{') depth++; else if (c === '}') { depth--; if (depth === 0) break; } }
  const body = htmlSrc.slice(i, j + 1);
  return new Function(...params.split(',').map(x => x.trim()), body.slice(1, -1));
}
const parseFlexibleDate = liftMethod('_parseFlexibleDate', 'raw');
const layoutLinkGraph = liftMethod('_layoutLinkGraph', 'nodes, edges, width, height');

const safe = fn => { try { return { ok: fn() }; } catch (e) { return { error: String(e && e.message || e) }; } };
const out = { fixtures: F, results: {} };
const R = out.results;

R.analyze = F.prompts.map(t => { const a = o.Analyzer.analyze(t); return { scores: a.scores, overall: a.overall, issues: a.issues, has: a.has, wordCount: a.wordCount, undefinedVars: a.undefinedVars }; });
R.profiles = {};
for (const p of o.CONFIG.SCORING_PROFILES.map(x => x.id)) R.profiles[p] = F.prompts.slice(0, 6).map(t => o.Analyzer.analyze(t, p).overall);
R.dna = F.prompts.map(t => o.Analyzer.dnaProfile(t, null).map(e => ({ id: e.id, strength: e.strength })));
R.improve = F.prompts.map(t => o.Analyzer.improve(t));
R.varSpecs = F.prompts.map(t => o.TemplateEngine.extractVariableSpecs(t).map(s => ({ name: s.name, type: s.type, default: s.default || '', options: s.options || [] })));
R.vars = F.prompts.map(t => o.TemplateEngine.extractVariables(t));
R.render = F.prompts.map(t => o.TemplateEngine.render(t, { topic: 'AI', document: 'DOC', audience: 'engineers', count: '5', tone: 'warm' }));
// VAR_RE is a /g regex, so the original's .test() carries lastIndex between calls and returns alternating answers
// for identical input. That is a latent bug in the HTML app; the golden records the intended (stateless) result.
R.hasUnfilled = F.prompts.map(t => { o.TemplateEngine.VAR_RE.lastIndex = 0; return o.TemplateEngine.hasUnfilledVariables(t); });
R.spans = F.prompts.map(t => o.TemplateEngine.detectParameterizableSpans(t));
R.humanize = ['user_name', 'targetAudience', 'x', 'long-variable-name_here'].map(n => [n, o.TemplateEngine.humanizeVarName(n)]);
R.inspect = F.prompts.map(t => o.PromptCleaner.inspect(t));
R.autoClean = F.prompts.map(t => o.PromptCleaner.autoClean(t));
R.security = F.prompts.map(t => o.SecurityScanner.scan(t));
R.risk = F.prompts.map(t => o.RiskLinter.scan(t));
R.injection = F.prompts.map(t => o.RiskLinter.checkInjectionSurface(t));
R.shorten = F.prompts.map(t => o.PromptTools.shorten(t));
R.bulletify = F.prompts.map(t => o.PromptTools.bulletify(t));
R.tableify = F.prompts.map(t => o.PromptTools.tableify(t));
R.cot = o.PromptTools.chainOfThoughtBlock();
R.tone = {}; for (const tn of F.tones) R.tone[tn] = F.prompts.map(t => o.PromptTools.toneShift(t, tn));
R.ambiguity = F.prompts.map(t => o.PromptTools.scanAmbiguity(t));
R.adversarial = F.prompts.map(t => o.PromptTools.scanAdversarial(t));
R.redundancy = F.prompts.map(t => o.PromptTools.findInternalRedundancy(t));
R.readability = F.prompts.map(t => o.ReadabilityEngine.analyze(t));
R.syllables = F.words.map(w => [w, o.ReadabilityEngine.countSyllables(w)]);
// Only validity is compared for JSON/XML: the original message text comes from the browser's parser.
R.validateJson = F.json.map(t => o.Validator.validate(t, 'json').valid);
R.validateXml = F.xml.map(t => o.Validator.validate(t, 'xml').valid);
R.embed = F.prompts.map(t => o.Validator.checkJSONEmbedSafety(t).map(e => ({ id: e.id, level: e.level })));
R.sections = F.sections.map(t => ['text', 'markdown', 'xml', 'json'].map(f => safe(() => o.FormatConverter.extractSections(t, f))));
R.convert = {};
for (const from of ['text', 'markdown', 'xml', 'json']) for (const to of ['text', 'markdown', 'xml', 'json'])
  if (from !== to) R.convert[`${from}>${to}`] = F.sections.map(t => safe(() => o.FormatConverter.convert(t, from, to)));
R.similarity = F.similarityPairs.map(([a, b]) => o.Utils.textSimilarity(a, b));
// The original diffWords returns { t, v } ops; the Dart port names them type/text.
R.diff = F.diffPairs.map(([a, b]) => o.Utils.diffWords(a, b).map(d => ({ type: d.t, text: d.v })));
R.tokenize = F.prompts.map(t => o.Utils.tokenize(t));
R.countWords = F.prompts.map(t => o.Utils.countWords(t));
R.csvEscape = F.csv.map(v => o.Utils.csvEscape(v));
R.truncate = F.truncate.map(([s, n]) => o.Utils.truncate(s, n));
R.escapeHtml = F.prompts.map(t => o.Utils.escapeHtml(t));
R.duplicates = (() => {
  const bodies = [
    'Write a detailed product description for a stainless steel water bottle aimed at hikers.',
    'Write a detailed product description for a stainless steel water bottle aimed at cyclists.',
    'Translate the following paragraph into formal French and keep the tone polite.',
    'short',
    'Translate the following paragraph into formal French and keep the tone very polite.',
    'Completely unrelated text about quarterly financial reporting and audit schedules.',
  ];
  const ps = bodies.map((body, i) => ({ id: 'p' + i, title: 'P' + i, body }));
  return { bodies, clusters: o.DuplicateFinder.findClusters(ps).map(c => c.map(p => p.id)) };
})();
R.splitSystemUser = F.prompts.map(t => o.MessageComposer.splitSystemUser(t));

// Exact cl100k token counts from the original RealTokenizer. Texts are chosen to stress the pre-tokenizer:
// contractions, digit grouping, unicode letters, emoji, CJK, code, runs of whitespace and newlines.
// Date parsing: results are reported as [year, month, day] (local time), or null, so the golden is timezone-proof.
const DATE_INPUTS = ['', '  ', 'today', 'Yesterday', '12 September 2026', '12th sep 2026', 'September 12th, 2026', 'sep 12 2026', 'ma 3 2026',
  '1 may 2026', '2026-09-12', '2026-9-2', '12/9/2026', '3-11-2026', '31 february 2026', '2026-13-40', 'foo 12 2026', '12 xyz 2026', 'next tuesday', '5 JANUARY 2025'];
R.dates = { inputs: DATE_INPUTS, parsed: DATE_INPUTS.map(t => { const d = parseFlexibleDate(t); return d && !isNaN(d) ? (t.trim().toLowerCase() === 'today' || t.trim().toLowerCase() === 'yesterday' ? 'relative' : [d.getFullYear(), d.getMonth() + 1, d.getDate()]) : null; }) };

// Force layout: a ring, a chain with a hub, an isolated pair, an empty graph and a single node.
const GRAPH_CASES = [
  { nodes: [], edges: [], w: 600, h: 560 },
  { nodes: ['a'], edges: [], w: 320, h: 560 },
  { nodes: ['a', 'b', 'c', 'd', 'e'], edges: [['a', 'b'], ['b', 'c'], ['c', 'd'], ['d', 'e'], ['e', 'a']], w: 600, h: 560 },
  { nodes: ['h', 'x1', 'x2', 'x3', 'x4', 'iso1', 'iso2'], edges: [['h', 'x1'], ['h', 'x2'], ['h', 'x3'], ['h', 'x4'], ['iso1', 'iso2'], ['x1', 'ghost']], w: 380, h: 560 },
  { nodes: Array.from({ length: 24 }, (_, i) => 'n' + i), edges: Array.from({ length: 30 }, (_, i) => ['n' + (i % 24), 'n' + ((i * 7 + 3) % 24)]), w: 900, h: 560 },
];
R.graph = GRAPH_CASES.map(c => {
  const pos = layoutLinkGraph(c.nodes.map(id => ({ id })), c.edges.map(([source, target]) => ({ source, target })), c.w, c.h);
  return { ...c, pos: Object.fromEntries([...pos.entries()].map(([k, v]) => [k, [v.x, v.y]])) };
});

const TOKEN_TEXTS = [
  '', 'a', 'Hello, world!', "I'm sure they're we've it'll she'd can't", 'The year 2026 has 365 days and 12345678 apples.',
  'def f(x):\n    return x ** 2  # square\n', 'line one\n\n\nline two   \t tabbed\r\nwindows', '   leading and trailing   ',
  'Café déjà vu naïve Straße Привет мир', '日本語のテキストと中文文本', 'Emoji 🚀🔥 and flags 🇮🇳 and 👨‍👩‍👧', '{"a": [1, 2, {"b": null}], "c": "d"}',
  '<system>You are a helpful assistant.</system>\n<user_input>{{user_input}}</user_input>', 'https://example.com/path?q=1&r=2#frag',
  '### Heading\n- bullet one\n- bullet two\n\n```js\nconst x = 1;\n```', 'ALLCAPS lowercase MiXeD camelCaseWord snake_case_word',
  'x'.repeat(200), 'The quick brown fox jumps over the lazy dog. '.repeat(20), '\n\n\n', ' ', '  a', 'a  ', '.....!!!??? --- ***',
];
R.tokens = { texts: TOKEN_TEXTS, counts: null };
(async () => {
  await o.RealTokenizer.warm();
  if (!o.RealTokenizer.isReady()) { console.error('RealTokenizer failed to load'); process.exit(1); }
  R.tokens.counts = TOKEN_TEXTS.map(t => o.RealTokenizer.countTokens(t));
  R.tokenEstimate = F.prompts.map(t => ({ gpt4o: o.TokenEstimator.estimateTokens(t, 'gpt4o'), claude: o.TokenEstimator.estimateTokens(t, 'claude'), gemini: o.TokenEstimator.estimateTokens(t, 'gemini') }));
  process.stdout.write(JSON.stringify(out, null, 1) + '\n');
})();
