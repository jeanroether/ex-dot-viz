defmodule ExDotViz do
  @moduledoc """
  Core API for the ExDotViz analyzer.

  This module provides a simple interface to:

    * scan a directory or a single file
    * parse Elixir source into ASTs
    * build module dependency and call graphs
    * render results as maps suitable for JSON and DOT backends
  """

  alias ExDotViz.{Scanner, Parser, Analyzer}

  @type path :: Path.t()
  @type path_arg :: Path.t() | charlist()

  @typedoc """
  Representation of a module in the analysis graph.

  Fields:

    * `:name` - atom module name (e.g. `MyApp.Foo`)
    * `:file` - source file where the module is defined
    * `:functions` - list of `%{name: atom(), arity: non_neg_integer()}`
  """
  @type module_node :: %{
          required(:name) => atom(),
          required(:file) => path(),
          required(:functions) => list(%{name: atom(), arity: non_neg_integer()})
        }

  @typedoc """
  Edge between modules (module dependency graph).
  """
  @type module_edge :: %{
          required(:from) => atom(),
          required(:to) => atom(),
          optional(:kind) => :call | :alias | :import | :use
        }

  @typedoc """
  Node in the call graph identified by `{module, function, arity}`.
  """
  @type call_node :: %{
          required(:mfa) => {atom(), atom(), non_neg_integer()}
        }

  @typedoc """
  Edge in the call graph.
  """
  @type call_edge :: %{
          required(:from) => {atom(), atom(), non_neg_integer()},
          required(:to) => {atom(), atom(), non_neg_integer()},
          optional(:kind) => :local | :remote
        }

  @typedoc """
  Aggregate analysis result.
  """
  @type analysis_result :: %{
          modules: list(module_node()),
          module_edges: list(module_edge()),
          module_call_edges: list(module_edge()),
          call_nodes: list(call_node()),
          call_edges: list(call_edge())
        }

  @doc """
  Analyze a directory (or single file) and return all graphs.

  Options:

    * `:include_tests` - when `false`, test files (`*_test.exs`) are skipped (default: `false`)
  """
  @spec analyze(path_arg(), keyword()) :: analysis_result()
  def analyze(path, opts \\ []) do
    include_tests? = Keyword.get(opts, :include_tests, false)

    files =
      Scanner.scan(path,
        include_tests?: include_tests?
      )

    forms = Parser.parse_files(files)

    Analyzer.build_graphs(forms)
  end
end
