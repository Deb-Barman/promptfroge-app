# Migration checklist: PromptForge.html → Flutter

Status key: **Verified** = covered by tests that compare against the original JavaScript, or by running tooling.
**Compiles** = analyzes clean against Flutter 3.50.0 but has not been run on a device. Nothing here has been run on a device yet.

Scope change requested by the owner: **no AI features, no backend; data lives in a user-chosen folder (Obsidian-style).**
Therefore AI, Supabase, auth, sync, API keys and SQLite/Drift were intentionally not built.

| Area | Original feature | Flutter location | Status |
|---|---|---|---|
| Storage | localStorage data | Vault folder of Markdown/JSON files (`lib/data/vault`) | Verified (repository + frontmatter tests) |
| Vault | pick / create folder, default vault, rescan, external-change detection | `vault_setup_screen`, `vault_notifier` | Compiles |
| Dashboard | stats, recents, quick actions, **quick capture**, first-run welcome | `dashboard_screen`, `quick_capture`, `onboarding` | Compiles |
| Editor | highlighted editor, gutter, undo/redo, autosave, find/replace, zen mode, **tab width, line height, word-count warning, live score chip** | `ui/screens/editor/*` | Compiles |
| Editor | suggestions (`/ // /// \ \\ @`, `{{var`, phrases), on/off setting | `search_engine`, `editor_screen` | Engine verified; UI compiles |
| Editor tools | Analyze (**exact tokens, per-section breakdown, monthly volume cost**), Scan, Transform, Variables, Copy as, Checklist | `editor_tools.dart` | Engines verified; UI compiles |
| Tokens | exact cl100k BPE for GPT models, estimate for others | `engines/bpe_tokenizer.dart` | **Verified** against the original tokenizer |
| Analyzer | scores, issues, DNA, improvements, scoring profiles | `engines/analyzer.dart` | **Verified** against the original |
| Templates | variables, fill dialog, templates + snippets, **groups, bulk select** | `templates_screen`, `groups_ui` | Compiles |
| Builder | blocks, reorder, structures (collapsible built-ins), custom sections, JSON structure import | `builder_screen` | Compiles |
| Library | search, filters, tags, groups (**rename/recolour**), favorites, sort, archive, saved searches, bulk actions, duplicates, **compare, diff pasted text** | `library_screen`, `external_diff` | Compiles |
| Patterns | built-in + user patterns, **All/Built-in/Yours tabs, groups, bulk select** | `patterns_screen` | Compiles |
| Chains | chains | `chains_screen` | Compiles |
| History | versions, restore, diff, **score sparkline, only-with-versions filter** | `history_screen` | Compiles |
| Compare | **2+ prompts**, score table per dimension, word diff for a pair, open in editor | `compare_screen` | Compiles |
| Date search | single date / range, 5 content types, 6 sorts, flexible date text | `date_search_screen`, `core/date_parse.dart` | Parser **verified**; UI compiles |
| Analytics | usage and quality stats | `analytics_screen` | Compiles |
| Learn | challenges with **saved answer + score per attempt** | `learn_screen` | Model verified; UI compiles |
| Graph | `[[wiki link]]` graph: **force-directed pan/zoom canvas** + list | `graph_screen`, `engines/graph_layout.dart` | Layout **verified**; UI compiles |
| Data | export (md/txt/csv/html), JSON backup, import, restore, **per-collection Clear** | `data_screen`, `settings_screen` | Compiles |
| Settings | theme, scoring profile, models, vault, **default category, tab width, line height, word-count warning, suggestions, live analyzer, replay welcome** | `settings_screen` | Compiles |
| CI / release | analyze, test, builds, release, Fastlane | `.github/workflows`, `fastlane` | Written; never run; needs your secrets for signing |

## Documented differences from the original

1. **Token counts:** exact for GPT-family models (the same cl100k tokenizer, ported and tested against the original); every other model
   uses the same characters-per-token estimate as the original. Before the ~150 ms vocabulary load finishes at startup, counts are estimates.
2. **No AI / backend / sync / accounts / API keys** (by request).
3. **Android needs All-files access** for a vault outside app storage; **iOS** may need the folder re-picked after reinstall.
4. **Platform folders (`android/`, `ios/`) are generated** by `tool/bootstrap.sh`, not committed.
5. **JSON export is the full backup only**, as in the original.
6. **Mobile adaptations:** keyboard shortcuts (Ctrl+K search, Alt+N quick capture, Tab indent) only apply with a hardware keyboard; the
   guided tour is a card sequence instead of highlighting the desktop rail; long lists scroll lazily instead of using page buttons.
7. **A solved Learn challenge stays solved** even if you later submit a weaker answer (the original overwrote it). The attempt itself is still recorded.
8. **Bug found in the original and not carried over:** `TemplateEngine.hasUnfilledVariables` used a global regex with `.test()`, which
   remembers its position between calls and returned alternating answers. The port is stateless.

## Verification still owed

A real `flutter build apk`, running the app on a phone (folder picking, the All-files permission, resume rescan, conflict banner, large
vaults), the widget tests, and the GitHub workflows. Static analysis (0 errors, 0 warnings) and the 338 headless tests already pass.
