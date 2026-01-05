defmodule ExDotViz.Dot do
  @moduledoc """
  DOT format renderers for module and call graphs.
  """

  @type dot_opt :: {:prune, [String.t()]}

  @doc """
  Render a module dependency graph in DOT format.
  """
  @spec module_graph(%{modules: [map()], module_edges: [map()]}, [dot_opt()]) :: String.t()
  def module_graph(%{modules: modules, module_edges: edges}, opts \\ []) do
    prune_set = opts |> Keyword.get(:prune, []) |> normalize_prune_list() |> MapSet.new()

    modules =
      Enum.reject(modules, fn %{name: name} ->
        MapSet.member?(prune_set, Atom.to_string(name))
      end)

    edges =
      Enum.reject(edges, fn %{from: from, to: to} ->
        MapSet.member?(prune_set, Atom.to_string(from)) or
          MapSet.member?(prune_set, Atom.to_string(to))
      end)

    nodes =
      Enum.map(modules, fn %{name: name} ->
        id = module_id(name)
        label = Atom.to_string(name)
        ~s(  #{id} [label="#{label}"];)
      end)

    edges_dot =
      Enum.map(edges, fn %{from: from, to: to, kind: kind} ->
        from_id = module_id(from)
        to_id = module_id(to)
        label = to_string(kind)
        ~s(  #{from_id} -> #{to_id} [label="#{label}"];)
      end)

    ["digraph modules {", "  rankdir=LR;"]
    |> Enum.concat(nodes)
    |> Enum.concat(edges_dot)
    |> Enum.concat(["}"])
    |> Enum.join("\n")
  end

  @doc """
  Render a call graph in DOT format.
  """
  @spec call_graph(%{call_nodes: [map()], call_edges: [map()]}) :: String.t()
  def call_graph(%{call_nodes: nodes, call_edges: edges}) do
    node_lines =
      Enum.map(nodes, fn %{mfa: {mod, fun, arity}} ->
        id = call_id({mod, fun, arity})
        label = "#{inspect(mod)}.#{fun}/#{arity}"
        ~s(  #{id} [label="#{label}"];)
      end)

    edge_lines =
      Enum.map(edges, fn %{from: from, to: to, kind: kind} ->
        from_id = call_id(from)
        to_id = call_id(to)
        style = if kind == :local, do: "solid", else: "dashed"
        ~s(  #{from_id} -> #{to_id} [style=#{style}];)
      end)

    ["digraph calls {", "  rankdir=LR;"]
    |> Enum.concat(node_lines)
    |> Enum.concat(edge_lines)
    |> Enum.concat(["}"])
    |> Enum.join("\n")
  end

  @doc """
  Render a module-level call graph in DOT format (aggregated function calls).
  """
  @spec module_call_graph(%{modules: [map()], module_call_edges: [map()]}, [dot_opt()]) ::
          String.t()
  def module_call_graph(%{modules: modules, module_call_edges: edges}, opts \\ []) do
    prune_set = opts |> Keyword.get(:prune, []) |> normalize_prune_list() |> MapSet.new()

    modules =
      Enum.reject(modules, fn %{name: name} ->
        MapSet.member?(prune_set, Atom.to_string(name))
      end)

    edges =
      Enum.reject(edges, fn %{from: from, to: to} ->
        MapSet.member?(prune_set, Atom.to_string(from)) or
          MapSet.member?(prune_set, Atom.to_string(to))
      end)

    module_names =
      modules
      |> Enum.map(& &1.name)
      |> MapSet.new()

    edge_names =
      edges
      |> Enum.flat_map(fn %{from: from, to: to} -> [from, to] end)
      |> Enum.reject(&is_nil/1)

    all_names =
      module_names
      |> MapSet.union(MapSet.new(edge_names))
      |> MapSet.to_list()

    nodes =
      Enum.map(all_names, fn name ->
        id = module_id(name)
        label = Atom.to_string(name)
        ~s(  #{id} [label="#{label}"];)
      end)

    edges_dot =
      Enum.map(edges, fn %{from: from, to: to} ->
        from_id = module_id(from)
        to_id = module_id(to)
        ~s(  #{from_id} -> #{to_id};)
      end)

    ["digraph module_calls {", "  rankdir=LR;"]
    |> Enum.concat(nodes)
    |> Enum.concat(edges_dot)
    |> Enum.concat(["}"])
    |> Enum.join("\n")
  end

  defp module_id(mod) do
    "m_" <>
      (mod
       |> Atom.to_string()
       |> String.replace(~r/[^a-zA-Z0-9_]/, "_"))
  end

  defp call_id({mod, fun, arity}) do
    "c_" <>
      (inspect({mod, fun, arity})
       |> String.replace(~r/[^a-zA-Z0-9_]/, "_"))
  end

  defp normalize_prune_list(items) do
    items
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn item ->
      if String.starts_with?(item, "Elixir."), do: item, else: "Elixir." <> item
    end)
  end
end
