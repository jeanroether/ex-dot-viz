## ExDotViz

**ExDotViz** is an automated Elixir code visualization tool.

It reads an Elixir project (or single file), extracts abstract syntax trees (ASTs),
builds **inter-module dependency graphs** and **call graphs**, and emits them as:

- **JSON** (for further tooling / custom visualization)
- **Graphviz DOT** (for direct rendering with Graphviz)

## Quick setup

```bash
cd ex-dot-viz
mix deps.get
mix escript.build
```

This produces the `ex_dot_viz` escript in the project root.

## Basic CLI usage

```bash
./ex_dot_viz PROJECT_PATH [--format json|dot] [--graph calls|module_calls|both] [--prune MOD1,MOD2,...]
```

Notes:

- Run the command from the ExDotViz tool directory.
- Output files are written to `./output/` (they are not printed to stdout).

## Visualize another project

Example target project:

`/Users/jean/Code/test_ex/absinthe`

From the ExDotViz directory:

```bash
# Module-level call graph (recommended starting point)
./ex_dot_viz path/to/lib --format json --graph module_calls
./ex_dot_viz path/to/lib --format dot --graph module_calls

# Function-level call graph (can be large)
./ex_dot_viz path/to/lib --format json --graph calls
./ex_dot_viz path/to/lib --format dot --graph calls
```

Generated files (in `./output/`):

- `module_calls.json` and `module_calls.dot`
- `calls.json` and `calls.dot`

To render a DOT file with Graphviz:

```bash
dot -Tsvg output/module_calls.dot -o module_calls.svg
dot -Tpng output/module_calls.dot -o module_calls.png
```

## Common examples

- Export both graphs as JSON:

  ```bash
  ./ex_dot_viz lib --format json --graph both
  # output/graphs.json
  ```

- Generate module dependency DOT and render as PNG:

  ```bash
  ./ex_dot_viz lib --format dot --graph module_calls
  dot -Tpng output/module_calls.dot -o module_calls.png
  ```

## Pruning (DOT-only)

If the generated DOT graphs are too large, you can **prune specific modules by name** when emitting DOT.

- Pruning applies only to DOT output.
- JSON output is **never pruned**.

The `--prune` option takes a comma-separated list of module names.
You can pass names with or without the `Elixir.` prefix.

## Programmatic usage (from an Elixir process)

```elixir
result = ExDotViz.analyze("lib")
json = ExDotViz.JSON.encode(result)
module_dot = ExDotViz.Dot.module_call_graph(result)
call_dot = ExDotViz.Dot.call_graph(result)
ExDotViz.JSON.encode(result)
```

License: see `LICENSE`.