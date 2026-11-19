const { load } = require('./load_original');
const o = load(process.argv[2]);
for (const n of ['Utils','TemplateEngine','Analyzer','SecurityScanner','PromptCleaner','PromptTools','Validator','FormatConverter','ReadabilityEngine','RiskLinter','DuplicateFinder','MessageComposer']) {
  for (const [k,v] of Object.entries(o[n])) if (typeof v === 'function') console.log(n+'.'+k, '(' + v.toString().match(/^[^(]*\(([^)]*)\)/)?.[1] + ')');
}
