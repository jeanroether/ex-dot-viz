defmodule ExDotViz.CLI do
  @moduledoc """
  Command-line interface for ExDotViz.

  This module is used as the escript entry point and can also be invoked from
  `mix run -e`.
  """

  alias ExDotViz.{JSON, Dot}

  @usage """
  Usage:
    ex_dot_viz PROJECT_PATH [OPTIONS]

  Options:
    --format/-f json|dot     Output format (default: json)
    --graph/-g modules|calls|module_calls|both  Graph type (default: module_calls)

  Examples:
    ex_dot_viz /path/to/my_project/lib
    ex_dot_viz /path/to/my_project/lib --format dot --graph modules
    ex_dot_viz /path/to/my_project/lib --format dot --graph module_calls
    ex_dot_viz /path/to/my_project/lib --format json --graph both

  The visualizations will be saved to: ./output/
  """

  @spec main([String.t()]) :: :ok
  def main(argv) do
    case parse_args(argv) do
      {:ok, project_path, format, graph} ->
        result = ExDotViz.analyze(project_path)
        output_dir = File.cwd!() |> Path.join("output")
        File.mkdir_p!(output_dir)

        case {format, graph} do
          {:json, :modules} ->
            json_output =
              JSON.encode(%{modules: result.modules, module_edges: result.module_edges})

            write_output(output_dir, "modules.json", json_output)
            IO.puts("✓ Saved modules.json")

          {:json, :all} ->
            json_output = JSON.encode(result)

            write_output(output_dir, "graphs.json", json_output)
            IO.puts("✓ Saved graphs.json")

          {:json, :calls} ->
            json_output =
              JSON.encode(%{call_nodes: result.call_nodes, call_edges: result.call_edges})

            write_output(output_dir, "calls.json", json_output)
            IO.puts("✓ Saved calls.json")

          {:json, :module_calls} ->
            json_output =
              JSON.encode(%{modules: result.modules, module_call_edges: result.module_call_edges})

            write_output(output_dir, "module_calls.json", json_output)
            IO.puts("✓ Saved module_calls.json")

          {:dot, :calls} ->
            dot_output =
              Dot.call_graph(%{call_nodes: result.call_nodes, call_edges: result.call_edges})

            write_output(output_dir, "calls.dot", dot_output)
            IO.puts("✓ Saved calls.dot")

          {:dot, :module_calls} ->
            dot_output =
              Dot.module_call_graph(%{
                modules: result.modules,
                module_call_edges: result.module_call_edges
              })

            write_output(output_dir, "module_calls.dot", dot_output)
            IO.puts("✓ Saved module_calls.dot")

          {:dot, :modules} ->
            dot_output =
              Dot.module_graph(%{modules: result.modules, module_edges: result.module_edges})

            write_output(output_dir, "modules.dot", dot_output)
            IO.puts("✓ Saved modules.dot")

          {:dot, :all} ->
            module_calls_dot =
              Dot.module_call_graph(%{
                modules: result.modules,
                module_call_edges: result.module_call_edges
              })

            calls_dot =
              Dot.call_graph(%{call_nodes: result.call_nodes, call_edges: result.call_edges})

            combined = "#{module_calls_dot}\n\n// Function-level call graph\n#{calls_dot}"
            write_output(output_dir, "graphs.dot", combined)
            IO.puts("✓ Saved graphs.dot")
        end

        IO.puts("\nOutput saved to: #{output_dir}")
        :ok

      :error ->
        IO.puts(@usage)
        :ok
    end
  end

  defp write_output(dir, filename, content) do
    filepath = Path.join(dir, filename)
    File.write!(filepath, content)
  end

  defp parse_args([path | rest]) do
    {opts, _rest, _invalid} =
      OptionParser.parse(rest,
        strict: [format: :string, graph: :string],
        aliases: [f: :format, g: :graph]
      )

    with {:ok, format} <- parse_format(Keyword.get(opts, :format, "json")),
         {:ok, graph} <- parse_graph(Keyword.get(opts, :graph, "both")) do
      {:ok, path, format, graph}
    else
      _ -> :error
    end
  end

  defp parse_args(_), do: :error

  defp parse_format("json"), do: {:ok, :json}
  defp parse_format("dot"), do: {:ok, :dot}
  defp parse_format(_), do: :error

  defp parse_graph("calls"), do: {:ok, :calls}
  defp parse_graph("modules"), do: {:ok, :modules}
  defp parse_graph("module_calls"), do: {:ok, :module_calls}
  defp parse_graph("both"), do: {:ok, :all}
  defp parse_graph(_), do: :error
end
