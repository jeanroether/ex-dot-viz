defmodule ExDotViz.Scanner do
  @moduledoc """
  Scans directories for Elixir source files.

  Supports `.ex` and `.exs` files. Test files ending in `_test.exs` can be
  optionally included via the `:include_tests?` option.
  """

  @type path :: Path.t()

  @doc """
  Return a list of Elixir source files rooted at `path`.

  If `path` is a regular file, it is returned as a single-element list when it
  has a supported extension.

  ## Options

    * `:include_tests?` (boolean) - whether to include `*_test.exs` files.
      Defaults to `false`.
  """
  @spec scan(path(), keyword()) :: [path()]
  def scan(path, opts \\ []) do
    include_tests? = Keyword.get(opts, :include_tests?, false)

    cond do
      File.regular?(path) ->
        if elixir_file?(path, include_tests?) do
          [path]
        else
          []
        end

      File.dir?(path) ->
        path
        |> Path.join("**/*.{ex,exs}")
        |> Path.wildcard()
        |> Enum.filter(&elixir_file?(&1, include_tests?))

      true ->
        []
    end
  end

  defp elixir_file?(file, include_tests?) do
    case Path.extname(file) do
      ".ex" ->
        true

      ".exs" ->
        include_tests? or not String.ends_with?(file, "_test.exs")

      _ ->
        false
    end
  end
end
