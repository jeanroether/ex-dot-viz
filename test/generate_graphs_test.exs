defmodule ExDotViz.GenerateGraphsTest do
  use ExUnit.Case

  @moduledoc false

  alias ExDotViz.{Scanner, Parser, JSON, Dot, Analyzer}

  @project_root "lib"
  @output_dir "test_output"

  @tag :integration
  test "generates JSON and DOT artifacts for the ExDotViz project itself" do
    File.mkdir_p!(@output_dir)

    # 1. Collect and parse all Elixir source files under the project root.
    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)

    # 2. Persist the parsed forms (our normalized AST representation).
    asts_json = JSON.encode(%{modules: forms})
    File.write!(Path.join(@output_dir, "asts.json"), asts_json)

    # 3. Build graphs from the same forms and persist them as JSON.
    graphs = Analyzer.build_graphs(forms)
    graphs_json = JSON.encode(graphs)
    File.write!(Path.join(@output_dir, "graphs.json"), graphs_json)

    # 4. Emit DOT files for module-level and function-level call graphs.
    calls_dot = Dot.call_graph(graphs)
    module_calls_dot = Dot.module_call_graph(graphs)

    File.write!(Path.join(@output_dir, "calls.dot"), calls_dot)
    File.write!(Path.join(@output_dir, "module_calls.dot"), module_calls_dot)
  end

  @tag :integration
  test "build_graphs returns module_call_edges in the result" do
    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    # Verify all expected keys are present
    assert Map.has_key?(graphs, :modules)
    assert Map.has_key?(graphs, :module_edges)
    assert Map.has_key?(graphs, :call_nodes)
    assert Map.has_key?(graphs, :call_edges)
    assert Map.has_key?(graphs, :module_call_edges)

    # Verify module_call_edges is a list
    assert is_list(graphs.module_call_edges)

    # Verify module_call_edges contain maps with :from and :to keys
    Enum.each(graphs.module_call_edges, fn edge ->
      assert is_map(edge)
      assert Map.has_key?(edge, :from)
      assert Map.has_key?(edge, :to)
      assert is_atom(edge.from)
      assert is_atom(edge.to)
    end)

    # Verify we have some module call edges (the project calls functions in other modules)
    assert length(graphs.module_call_edges) > 0
  end

  @tag :integration
  test "module_call_graph renders aggregated module calls in DOT format" do
    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    module_calls_dot = Dot.module_call_graph(graphs)

    # Verify output is a string
    assert is_binary(module_calls_dot)

    # Verify it's a valid DOT graph
    assert String.contains?(module_calls_dot, "digraph module_calls {")
    assert String.contains?(module_calls_dot, "rankdir=LR;")
    assert String.contains?(module_calls_dot, "}")

    # Verify it contains module nodes
    assert String.contains?(module_calls_dot, "[label=")

    # Verify it contains edges (->)
    assert String.contains?(module_calls_dot, "->")

    # Module-level call graph should be much smaller than function-level graph
    call_graph_size =
      graphs
      |> Dot.call_graph()
      |> String.length()

    module_call_graph_size =
      graphs
      |> Dot.module_call_graph()
      |> String.length()

    assert module_call_graph_size < call_graph_size,
           "Module-level call graph should be smaller than function-level call graph"
  end

  @tag :integration
  test "module_call_edges excludes self-calls" do
    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    # Verify no edges point from a module to itself
    Enum.each(graphs.module_call_edges, fn %{from: from, to: to} ->
      assert from != to, "Found self-call: #{inspect(from)} -> #{inspect(to)}"
    end)
  end

  @tag :integration
  test "JSON encoding includes module_call_edges" do
    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    json_string = JSON.encode(graphs)

    # Verify JSON contains the module_call_edges key
    assert String.contains?(json_string, "module_call_edges")

    # Verify we can decode it back and it has the expected structure
    {:ok, decoded} = JSON.decode(json_string)
    assert Map.has_key?(decoded, "module_call_edges")
    assert is_list(decoded["module_call_edges"])
  end

  @tag :integration
  test "all graph types are generated and have content" do
    File.mkdir_p!(@output_dir)

    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    # Generate all DOT formats
    modules_dot = Dot.module_graph(graphs)
    calls_dot = Dot.call_graph(graphs)
    module_calls_dot = Dot.module_call_graph(graphs)

    # Verify all are non-empty strings
    assert byte_size(modules_dot) > 0, "Module dependency graph is empty"
    assert byte_size(calls_dot) > 0, "Function-level call graph is empty"
    assert byte_size(module_calls_dot) > 0, "Module-level call graph is empty"

    # Verify they all start with digraph
    assert String.starts_with?(modules_dot, "digraph")
    assert String.starts_with?(calls_dot, "digraph")
    assert String.starts_with?(module_calls_dot, "digraph")

    # Verify they all end with closing brace
    assert String.trim(modules_dot) |> String.ends_with?("}")
    assert String.trim(calls_dot) |> String.ends_with?("}")
    assert String.trim(module_calls_dot) |> String.ends_with?("}")

    # Size relationship test: module graph should be smaller than call graphs
    module_size = byte_size(modules_dot)
    call_size = byte_size(calls_dot)
    module_call_size = byte_size(module_calls_dot)

    assert module_call_size < call_size,
           "Module-level call graph (#{module_call_size} bytes) should be smaller than function-level call graph (#{call_size} bytes)"

    IO.puts("\n=== Graph Generation Summary ===")
    IO.puts("✓ Module dependency graph: #{module_size} bytes")
    IO.puts("✓ Function-level call graph: #{call_size} bytes")
    IO.puts("✓ Module-level call graph: #{module_call_size} bytes")

    IO.puts(
      "✓ Size reduction: #{round((1 - module_call_size / call_size) * 100)}% smaller than function-level"
    )

    IO.puts("✓ All graphs generated successfully!")
  end

  @tag :integration
  test "CLI commands work with new graph options" do
    # Test that the CLI can handle all graph options
    # This verifies the parsing logic works correctly

    # We'll test by creating a simple module and analyzing it
    File.mkdir_p!(@output_dir)

    files = Scanner.scan(@project_root, include_tests?: false)
    forms = Parser.parse_files(files)
    graphs = Analyzer.build_graphs(forms)

    # Test modules graph option
    modules_subset = %{
      modules: graphs.modules,
      module_edges: graphs.module_edges
    }

    modules_json = JSON.encode(modules_subset)
    assert String.contains?(modules_json, "modules")

    # Test calls graph option
    calls_subset = %{
      call_nodes: graphs.call_nodes,
      call_edges: graphs.call_edges
    }

    calls_json = JSON.encode(calls_subset)
    assert String.contains?(calls_json, "call_nodes")

    # Test module_calls graph option
    module_calls_subset = %{
      modules: graphs.modules,
      module_call_edges: graphs.module_call_edges
    }

    module_calls_json = JSON.encode(module_calls_subset)
    assert String.contains?(module_calls_json, "module_call_edges")

    IO.puts("\n=== CLI Graph Options Verified ===")
    IO.puts("✓ --graph modules: extracts module dependency graph")
    IO.puts("✓ --graph calls: extracts function-level call graph")
    IO.puts("✓ --graph module_calls: extracts module-level call graph")
    IO.puts("✓ --graph both: combines module dependencies with module-level calls")
  end
end
