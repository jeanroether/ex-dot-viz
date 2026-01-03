defmodule ExDotViz.JSON do
  @moduledoc """
  Minimal JSON encoder for ExDotViz data structures.

  This avoids external dependencies by handling only the subset of Elixir terms
  we care about: maps with string/atom keys, lists, numbers, booleans, and
  strings/atoms/tuples.
  """

  @doc """
  Encode an Elixir term as a human-readable JSON string.
  """
  @spec encode(term()) :: String.t()
  def encode(term), do: encode(term, pretty: true)

  @doc """
  Encode an Elixir term as JSON with optional pretty-printing.
  """
  @spec encode(term(), keyword()) :: String.t()
  def encode(term, opts) do
    pretty? = Keyword.get(opts, :pretty, false)
    do_encode(term, pretty?: pretty?, indent: 0)
  end

  defp do_encode(nil, _ctx), do: "null"
  defp do_encode(true, _ctx), do: "true"
  defp do_encode(false, _ctx), do: "false"

  defp do_encode(n, _ctx) when is_integer(n) or is_float(n) do
    :erlang.float_to_binary(n, [:compact])
  rescue
    _ -> Integer.to_string(n)
  end

  defp do_encode(atom, ctx) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> do_encode(ctx)
  end

  defp do_encode(binary, _ctx) when is_binary(binary) do
    escaped =
      binary
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end

  defp do_encode(list, ctx) when is_list(list) do
    pretty? = Keyword.get(ctx, :pretty?, false)
    indent = Keyword.get(ctx, :indent, 0)

    elems =
      Enum.map(list, fn v ->
        do_encode(v, Keyword.put(ctx, :indent, indent + 2))
      end)

    case {pretty?, elems} do
      {false, _} ->
        "[" <> Enum.join(elems, ",") <> "]"

      {true, []} ->
        "[]"

      {true, _} ->
        newline = "\n"
        space = String.duplicate(" ", indent + 2)
        inner = Enum.join(Enum.map(elems, &"#{space}#{&1}"), ",\n")
        closing = String.duplicate(" ", indent)
        "[" <> newline <> inner <> newline <> closing <> "]"
    end
  end

  defp do_encode(%{} = map, ctx) do
    pretty? = Keyword.get(ctx, :pretty?, false)
    indent = Keyword.get(ctx, :indent, 0)

    pairs =
      map
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} ->
        key_json = do_encode(k, Keyword.put(ctx, :indent, indent + 2))
        value_json = do_encode(v, Keyword.put(ctx, :indent, indent + 2))
        {key_json, value_json}
      end)

    case {pretty?, pairs} do
      {false, _} ->
        inner =
          pairs
          |> Enum.map(fn {k, v} -> k <> ":" <> v end)
          |> Enum.join(",")

        "{" <> inner <> "}"

      {true, []} ->
        "{}"

      {true, _} ->
        newline = "\n"
        space = String.duplicate(" ", indent + 2)

        inner =
          pairs
          |> Enum.map(fn {k, v} -> "#{space}#{k}: #{v}" end)
          |> Enum.join(",\n")

        closing = String.duplicate(" ", indent)
        "{" <> newline <> inner <> newline <> closing <> "}"
    end
  end

  defp do_encode({a, b, c}, ctx) do
    do_encode([a, b, c], ctx)
  end

  @doc """
  Decode a JSON string into Elixir terms (basic implementation).
  Returns {:ok, term} on success, {:error, reason} on failure.
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, String.t()}
  def decode(json_string) when is_binary(json_string) do
    json_string = String.trim(json_string)

    case parse_value(json_string) do
      {value, ""} -> {:ok, value}
      {_value, _rest} -> {:error, "Extra characters after JSON"}
      :error -> {:error, "Invalid JSON"}
    end
  end

  defp parse_value(json) do
    json = String.trim_leading(json)

    cond do
      String.starts_with?(json, "null") -> {nil, String.slice(json, 4..-1//1)}
      String.starts_with?(json, "true") -> {true, String.slice(json, 4..-1//1)}
      String.starts_with?(json, "false") -> {false, String.slice(json, 5..-1//1)}
      String.starts_with?(json, "\"") -> parse_string(json)
      String.starts_with?(json, "[") -> parse_array(json)
      String.starts_with?(json, "{") -> parse_object(json)
      String.starts_with?(json, "-") or String.match?(json, ~r/^\d/) -> parse_number(json)
      true -> :error
    end
  end

  defp parse_string("\"" <> rest) do
    case parse_string_content(rest, "") do
      {value, rest} -> {value, rest}
      :error -> :error
    end
  end

  defp parse_string_content("\"" <> rest, acc), do: {acc, rest}

  defp parse_string_content("\\" <> <<char::utf8>> <> rest, acc) do
    unescaped =
      case char do
        ?n -> "\n"
        ?r -> "\r"
        ?t -> "\t"
        ?\\ -> "\\"
        ?" -> "\""
        ?/ -> "/"
        ?b -> "\b"
        ?f -> "\f"
        _ -> <<char::utf8>>
      end

    parse_string_content(rest, acc <> unescaped)
  end

  defp parse_string_content(<<char::utf8>> <> rest, acc) do
    parse_string_content(rest, acc <> <<char::utf8>>)
  end

  defp parse_string_content("", _acc), do: :error

  defp parse_array("[" <> rest) do
    rest = String.trim_leading(rest)

    if String.starts_with?(rest, "]") do
      {[], String.slice(rest, 1..-1//1)}
    else
      parse_array_elements(rest, [])
    end
  end

  defp parse_array_elements(json, acc) do
    case parse_value(json) do
      :error ->
        :error

      {value, rest} ->
        rest = String.trim_leading(rest)

        cond do
          String.starts_with?(rest, ",") ->
            parse_array_elements(String.trim_leading(String.slice(rest, 1..-1//1)), acc ++ [value])

          String.starts_with?(rest, "]") ->
            {Enum.reverse([value | Enum.reverse(acc)]), String.slice(rest, 1..-1//1)}

          true ->
            :error
        end
    end
  end

  defp parse_object("{" <> rest) do
    rest = String.trim_leading(rest)

    if String.starts_with?(rest, "}") do
      {%{}, String.slice(rest, 1..-1//1)}
    else
      parse_object_pairs(rest, %{})
    end
  end

  defp parse_object_pairs(json, acc) do
    case parse_string(json) do
      {key, rest} ->
        rest = String.trim_leading(rest)

        if String.starts_with?(rest, ":") do
          case parse_value(String.trim_leading(String.slice(rest, 1..-1//1))) do
            {value, rest} ->
              rest = String.trim_leading(rest)

              cond do
                String.starts_with?(rest, ",") ->
                  parse_object_pairs(
                    String.trim_leading(String.slice(rest, 1..-1//1)),
                    Map.put(acc, key, value)
                  )

                String.starts_with?(rest, "}") ->
                  {Map.put(acc, key, value), String.slice(rest, 1..-1//1)}

                true ->
                  :error
              end

            :error ->
              :error
          end
        else
          :error
        end

      :error ->
        :error
    end
  end

  defp parse_number(json) do
    case Integer.parse(json) do
      {num, rest} ->
        {num, rest}

      :error ->
        case Float.parse(json) do
          {num, rest} -> {num, rest}
          :error -> :error
        end
    end
  end
end
