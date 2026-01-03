## ExDotViz

**ExDotViz** is an automated Elixir code visualization tool.

It reads an Elixir project (or single file), extracts abstract syntax trees (ASTs),
builds **inter-module dependency graphs** and **call graphs**, and emits them as:

- **JSON** (for further tooling / custom visualization)
- **Graphviz DOT** (for direct rendering with Graphviz)
## ExDotViz

Quick setup

```bash
cd ex-dot-viz
mix deps.get
mix escript.build
```

This produces the `ex_dot_viz` escript in the project root.

Basic CLI usage

```bash
./ex_dot_viz PATH --format json|dot --graph calls|module_calls|both
```

Common examples

- Export both graphs as JSON:

  ```bash
  ./ex_dot_viz lib --format json --graph both > graphs.json
  ```

- Generate module dependency DOT and render as PNG:

  ```bash
  ./ex_dot_viz lib --format dot --graph module_calls > module_calls.dot
  dot -Tpng module_calls.dot -o module_calls.png
  ```

Programmatic usage (from an Elixir process)

```elixir
result = ExDotViz.analyze("lib")
json = ExDotViz.JSON.encode(result)
module_dot = ExDotViz.Dot.module_call_graph(result)
call_dot = ExDotViz.Dot.call_graph(result)
ExDotViz.JSON.encode(result)
```

License: see `LICENSE`.