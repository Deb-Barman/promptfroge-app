# Golden generator

`gen_goldens.js` loads the original `reference/PromptForge.html` scripts into node's `vm` (`load_original.js`), runs
every engine over the prompts in `fixtures.js`, and writes `test/goldens/engines.json`. The Dart tests in
`test/engines/golden_engines_test.dart` compare the Dart engines to that file, so the port is checked against the
original behaviour rather than against hand-written expectations.

    node tool/golden/gen_goldens.js        # regenerate
    git diff --exit-code test/goldens      # CI does this

Add a fixture to `fixtures.js` when you find a case the port gets wrong, then regenerate.
`sigs.js` lists the engine entry points exercised.
