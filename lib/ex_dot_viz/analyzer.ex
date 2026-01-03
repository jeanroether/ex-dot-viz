defmodule ExDotViz.Analyzer do
  @moduledoc """
  Builds graphs (module dependency graph and call graph) from parsed forms.
  """

  alias ExDotViz.Parser

  @type module_form :: Parser.module_form()

  @spec build_graphs([module_form()]) :: %{
          modules: [map()],
          module_edges: [map()],
          call_nodes: [map()],
          call_edges: [map()],
          module_call_edges: [map()]
        }
  def build_graphs(forms) do
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

    %{
      modules: modules,
      module_edges: module_edges,
      call_nodes: call_nodes,
      call_edges: Enum.reverse(call_edges),
      module_call_edges: module_call_edges
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
    |> Enum.reject(fn {target, _} -> target == form.name end)
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
