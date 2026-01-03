defmodule ExDotViz.Analyzer do
  @moduledoc """
  Builds graphs (module dependency graph and call graph) from parsed forms.
  """

  alias ExDotViz.Parser

  @type module_form :: Parser.module_form()

  @spec build_graphs([module_form()], keyword()) :: %{
          modules: [map()],
          module_edges: [map()],
          call_nodes: [map()],
          call_edges: [map()],
          module_call_edges: [map()]
        }
  def build_graphs(forms, opts \\ []) do
    internal_only? = Keyword.get(opts, :internal_only, true)

    modules =
      Enum.map(forms, fn form ->
        %{
          name: form.name,
          file: form.file,
          functions: form.functions
        }
      end)

    module_edges =
      forms
      |> Enum.flat_map(&module_edges_for_form/1)
      |> Enum.uniq()

    {call_nodes_set, call_edges} =
      forms
      |> Enum.reduce({MapSet.new(), []}, fn form, {nodes, edges} ->
        nodes =
          Enum.reduce(form.functions, nodes, fn %{name: name, arity: arity}, acc ->
            MapSet.put(acc, {form.name, name, arity})
          end)

        edges =
          Enum.reduce(form.calls, edges, fn call, acc ->
            [%{kind: call.kind, from: call.from, to: call.to} | acc]
          end)

        {nodes, edges}
      end)

    call_nodes =
      call_nodes_set
      |> Enum.sort()
      |> Enum.map(fn {mod, fun, arity} ->
        %{mfa: {mod, fun, arity}}
      end)

    module_call_edges =
      forms
      |> Enum.flat_map(&module_call_edges_for_form/1)
      |> Enum.uniq()

    graphs = %{
      modules: modules,
      module_edges: module_edges,
      call_nodes: call_nodes,
      call_edges: Enum.reverse(call_edges),
      module_call_edges: module_call_edges
    }

    if internal_only? do
      filter_internal(graphs)
    else
      graphs
    end
  end

  defp filter_internal(%{modules: modules} = graphs) do
    internal_modules =
      modules
      |> Enum.map(& &1.name)
      |> MapSet.new()

    module_edges =
      graphs.module_edges
      |> Enum.filter(fn %{from: from, to: to} ->
        MapSet.member?(internal_modules, from) and MapSet.member?(internal_modules, to)
      end)

    module_call_edges =
      graphs.module_call_edges
      |> Enum.filter(fn %{from: from, to: to} ->
        MapSet.member?(internal_modules, from) and MapSet.member?(internal_modules, to)
      end)

    call_edges =
      graphs.call_edges
      |> Enum.filter(fn %{
                          from: {from_mod, _from_fun, _from_arity},
                          to: {to_mod, _to_fun, _to_arity}
                        } ->
        MapSet.member?(internal_modules, from_mod) and MapSet.member?(internal_modules, to_mod)
      end)

    used_mfas =
      Enum.reduce(call_edges, MapSet.new(), fn %{from: from, to: to}, acc ->
        acc
        |> MapSet.put(from)
        |> MapSet.put(to)
      end)

    call_nodes =
      graphs.call_nodes
      |> Enum.filter(fn %{mfa: mfa} -> MapSet.member?(used_mfas, mfa) end)

    %{
      graphs
      | module_edges: module_edges,
        module_call_edges: module_call_edges,
        call_edges: call_edges,
        call_nodes: call_nodes
    }
  end

  defp module_edges_for_form(form) do
    calls =
      Enum.map(form.calls, fn %{to: {mod, _fun, _arity}} ->
        {mod, :call}
      end)

    refs =
      Enum.map(form.refs, fn %{kind: kind, target: mod} ->
        {mod, kind}
      end)

    calls
    |> Enum.concat(refs)
    |> Enum.reject(fn {target, _} -> target in [:unknown, form.name] end)
    |> Enum.map(fn {target, kind} ->
      %{
        from: form.name,
        to: target,
        kind: kind
      }
    end)
  end

  defp module_call_edges_for_form(form) do
    form.calls
    |> Enum.map(fn %{to: {to_mod, _fun, _arity}} ->
      {form.name, to_mod}
    end)
    |> Enum.reject(fn {from, to} -> from == to end)
    |> Enum.uniq()
    |> Enum.map(fn {from, to} ->
      %{from: from, to: to}
    end)
  end
end
