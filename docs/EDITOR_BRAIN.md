# Editor brain & Obsidian-style graph

## The brain (`lib/domain/engines/brain.dart`)

A small statistical language model that is built **on the device** from everything in the vault:
prompts, templates, patterns, snippets and chains (built-in patterns and a tiny word list only seed day one
and are never counted as "learned"). No AI service, no network.

* **Learns:** word frequencies, bigrams and trigrams, usual sentence starts, `{{variables}}`, and which
  prompt sections (Role, Task, Constraints, …) you write and which ones you write together.
* **Completes while you type:** two or more letters open a compact popup under the caret with words first,
  then short phrases. A completion must save at least two characters.
* **Predicts after a space:** the strip above the keyboard offers the next word or phrase when the brain is
  confident enough.
* **Ranks the section chips:** missing sections you usually write next to the ones already in the prompt get a
  sparkle; sections already present move to the end with a check.
* **Gets smarter on its own:** after any change to the vault it relearns in the background (a few seconds after
  you stop typing; in an isolate for large vaults). Level 1 Seed → 8 Oracle, shown on the editor rail, in the
  status bar and in the Brain sheet.
* **Personal ranking:** accepted words and phrases are remembered on the device (`brain_usage_v1`) and rank higher.

Everything is deterministic and unit-tested (`test/engines/brain_test.dart`).

## The graph (`lib/ui/screens/graph_screen.dart`, `lib/domain/engines/graph_sim.dart`)

A live force simulation (d3-force style) drawn on a custom canvas: drag nodes, pin them, pan and pinch-zoom,
tap to highlight a node and its neighbours, labels fade in with zoom, forces panel (center / repel / link /
distance / node size / label fade), local-graph focus (1–3 steps), orphan and label toggles, colour by
category or by links, search highlight, and a time-lapse of how the vault grew. Dashed violet lines are the
brain's "related" links (TF-IDF similarity); solid lines are real `[[wiki links]]`.
