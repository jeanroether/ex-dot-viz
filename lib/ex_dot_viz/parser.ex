defmodule ExDotViz.Parser do
  @moduledoc """
  Parses Elixir source files into a normalized intermediate representation.

  Each file is parsed into a list of module forms, capturing:

    * module name
    * defining file
    * function definitions (name/arity)
    * call sites (local and remote)
    * simple alias/import/use references for dependency analysis
  """

  @type path :: Path.t()

  @type fun_sig :: %{name: atom(), arity: non_neg_integer()}

  @type call_site :: %{
          kind: :local | :remote,
          from: {atom(), atom(), non_neg_integer()},
          to: {atom(), atom(), non_neg_integer() | :unknown}
        }

  @type ref :: %{
          kind: :alias | :import | :use,
          target: atom()
        }

  @type module_form :: %{
          name: atom(),
          file: path(),
          functions: [fun_sig()],
          calls: [call_site()],
      refs: [ref()]
        }

  @spec parse_files([path()]) :: [module_form()]
  def parse_files(files) do
    Enum.flat_map(files, &parse_file/1)
  end

  @spec parse_file(path()) :: [module_form()]
  def parse_file(file) do
    case File.read(file) do
      {:ok, source} ->
        parse_string(source, file)

      {:error, _} ->
        []
    end
  end

  @spec parse_string(String.t(), path()) :: [module_form()]
  def parse_string(source, file) do
    case Code.string_to_quoted(source, file: file) do
      {:ok, ast} ->
        extract_modules(ast, file)

      {:error, _} ->
        []
    end
  end

  defp extract_modules({:__block__, _, forms}, file) do
    forms
    |> Enum.flat_map(&extract_modules(&1, file))
  end

  defp extract_modules({:defmodule, _, [mod_ast, [do: body]]}, file) do
    name = module_name(mod_ast)

    acc =
      walk_body(body, name, %{
        functions: MapSet.new(),
        calls: [],
        refs: [],
        aliases: %{}
      })

    funs = acc.functions
    calls = acc.calls
    refs = acc.refs

    [
      %{
        name: name,
        file: file,
        functions:
          funs
          |> Enum.map(fn {fun, arity} -> %{name: fun, arity: arity} end)
          |> Enum.sort_by(&{&1.name, &1.arity}),
        calls: Enum.reverse(calls),
        refs: Enum.reverse(refs)
      }
    ]
  end

  defp extract_modules(_other, _file), do: []

  defp module_name(ast), do: module_name(ast, :unknown)

  defp module_name(ast, current_mod), do: module_name(ast, current_mod, %{})

  defp module_name({:__aliases__, _, parts}, current_mod, aliases) when is_list(parts) do
    resolved_parts = resolve_alias_parts(parts, current_mod, aliases)

    if Enum.any?(resolved_parts, &(&1 == :unknown)) do
      :unknown
    else
      Module.concat(resolved_parts)
    end
  end

  defp module_name({:__MODULE__, _, _}, current_mod, _aliases) when is_atom(current_mod), do: current_mod

  defp module_name({:unquote, _, [inner]}, current_mod, aliases) do
    resolve_alias_part(inner, current_mod, aliases)
  end

  # Handles simple atoms like :foo and tuple AST nodes like {:foo, meta, args}
  defp module_name({name, _, _}, _current_mod, _aliases) when is_atom(name), do: name

  defp module_name(atom, _current_mod, _aliases) when is_atom(atom), do: atom

  # Fallback for unexpected shapes – return a sentinel so callers can choose to ignore it.
  defp module_name(_other, _current_mod, _aliases), do: :unknown

  defp resolve_alias_parts([], _current_mod, _aliases), do: []

  defp resolve_alias_parts([first | rest], current_mod, aliases) do
    case resolve_alias_part(first, current_mod, aliases) do
      :unknown ->
        [:unknown | Enum.map(rest, &resolve_alias_part(&1, current_mod, aliases))]

      resolved_first ->
        case Map.fetch(aliases, resolved_first) do
          {:ok, expanded_mod} ->
            expanded_parts =
              expanded_mod
              |> Module.split()
              |> Enum.map(&String.to_atom/1)

            expanded_parts ++ Enum.map(rest, &resolve_alias_part(&1, current_mod, aliases))

          :error ->
            [resolved_first | Enum.map(rest, &resolve_alias_part(&1, current_mod, aliases))]
        end
    end
  end

  defp resolve_alias_part(part, _current_mod, _aliases) when is_atom(part), do: part

  defp resolve_alias_part({:__MODULE__, _, _}, current_mod, _aliases) when is_atom(current_mod),
    do: current_mod

  defp resolve_alias_part({:unquote, _, [inner]}, current_mod, aliases),
    do: resolve_alias_part(inner, current_mod, aliases)

  defp resolve_alias_part(_other, _current_mod, _aliases), do: :unknown

  defp alias_pairs({:__aliases__, _, parts}, _current_mod) when is_list(parts) do
    full = Module.concat(parts)
    short = parts |> List.last()
    [{short, full}]
  end

  # Handles `alias MyApp.{Foo, Bar}`.
  defp alias_pairs({{:., _, [base_ast, :{}]}, _, children}, current_mod)
       when is_list(children) do
    base_mod = module_name(base_ast, current_mod, %{})

    if base_mod == :unknown do
      []
    else
      base_parts =
        base_mod
        |> Module.split()
        |> Enum.map(&String.to_atom/1)

      Enum.flat_map(children, fn
        {:__aliases__, _, child_parts} when is_list(child_parts) ->
          full = Module.concat(base_parts ++ child_parts)
          short = child_parts |> List.last()
          [{short, full}]

        _other ->
          []
      end)
    end
  end

  defp alias_pairs(_other, _current_mod), do: []

  defp walk_body({:__block__, _, forms}, mod, acc) do
    Enum.reduce(forms, acc, &walk_body(&1, mod, &2))
  end

  defp walk_body({:alias, _, [alias_ast]} = _node, mod, acc) do
    target = module_name(alias_ast, mod, acc.aliases)
    ref = %{kind: :alias, target: target}

    acc
    |> Map.update!(:refs, fn refs -> [ref | refs] end)
    |> Map.update!(:aliases, fn aliases ->
      alias_ast
      |> alias_pairs(mod)
      |> Enum.reduce(aliases, fn {short, full}, acc_aliases ->
        Map.put(acc_aliases, short, full)
      end)
    end)
  end

  defp walk_body({:alias, _, [alias_ast, opts]} = _node, mod, acc) when is_list(opts) do
    target = module_name(alias_ast, mod, acc.aliases)

    acc
    |> Map.update!(:refs, fn refs -> [%{kind: :alias, target: target} | refs] end)
    |> Map.update!(:aliases, fn aliases ->
      case Keyword.get(opts, :as) do
        {:__aliases__, _, [as_name]} when is_atom(as_name) and is_atom(target) ->
          Map.put(aliases, as_name, target)

        _ ->
          alias_ast
          |> alias_pairs(mod)
          |> Enum.reduce(aliases, fn {short, full}, acc_aliases ->
            Map.put(acc_aliases, short, full)
          end)
      end
    end)
  end

  defp walk_body({:import, _, [alias_ast | _]} = _node, mod, acc) do
    target = module_name(alias_ast, mod, acc.aliases)
    ref = %{kind: :import, target: target}
    Map.update!(acc, :refs, fn refs -> [ref | refs] end)
  end

  defp walk_body({:use, _, [alias_ast | _]} = _node, mod, acc) do
    target = module_name(alias_ast, mod, acc.aliases)
    ref = %{kind: :use, target: target}
    Map.update!(acc, :refs, fn refs -> [ref | refs] end)
  end

  defp walk_body({kind, _, [{name, _, args_ast} = _head, body]}, mod, acc)
       when kind in [:def, :defp] and is_atom(name) do
    arity = length(args_ast || [])
    fun_sig = {name, arity}

    acc =
      Map.update!(acc, :functions, fn set ->
        MapSet.put(set, fun_sig)
      end)

    from = {mod, name, arity}

    {_ignored_node, acc} =
      Macro.prewalk(body, acc, fn
        {{:., _, [remote_mod_ast, remote_fun]}, _, call_args} = call, acc2
        when is_atom(remote_fun) ->
          remote_mod = module_name(remote_mod_ast, mod, acc2.aliases)
          arity2 = length(call_args || [])

          call_site = %{
            kind: :remote,
            from: from,
            to: {remote_mod, remote_fun, arity2}
          }

          {call,
           Map.update!(acc2, :calls, fn calls ->
             [call_site | calls]
           end)}

        {local_fun, _, call_args} = call, acc2
        when is_atom(local_fun) and local_fun not in [:def, :defp] ->
          arity2 = length(call_args || [])

          call_site = %{
            kind: :local,
            from: from,
            to: {mod, local_fun, arity2}
          }

          {call,
           Map.update!(acc2, :calls, fn calls ->
             [call_site | calls]
           end)}

        {:alias, _, [alias_ast]} = node2, acc2 ->
          target = module_name(alias_ast, mod, acc2.aliases)

          ref = %{kind: :alias, target: target}

          {node2,
           acc2
           |> Map.update!(:refs, fn refs -> [ref | refs] end)
           |> Map.update!(:aliases, fn aliases ->
             alias_ast
             |> alias_pairs(mod)
             |> Enum.reduce(aliases, fn {short, full}, acc_aliases ->
               Map.put(acc_aliases, short, full)
             end)
           end)}

        {:alias, _, [alias_ast, opts]} = node2, acc2 when is_list(opts) ->
          target = module_name(alias_ast, mod, acc2.aliases)

          {node2,
           acc2
           |> Map.update!(:refs, fn refs -> [%{kind: :alias, target: target} | refs] end)
           |> Map.update!(:aliases, fn aliases ->
             case Keyword.get(opts, :as) do
               {:__aliases__, _, [as_name]} when is_atom(as_name) and is_atom(target) ->
                 Map.put(aliases, as_name, target)

               _ ->
                 alias_ast
                 |> alias_pairs(mod)
                 |> Enum.reduce(aliases, fn {short, full}, acc_aliases ->
                   Map.put(acc_aliases, short, full)
                 end)
             end
           end)}

        {:import, _, [alias_ast | _]} = node2, acc2 ->
          target = module_name(alias_ast, mod, acc2.aliases)

          ref = %{kind: :import, target: target}

          {node2,
           Map.update!(acc2, :refs, fn refs ->
             [ref | refs]
           end)}

        {:use, _, [alias_ast | _]} = node2, acc2 ->
          target = module_name(alias_ast, mod, acc2.aliases)

          ref = %{kind: :use, target: target}

          {node2,
           Map.update!(acc2, :refs, fn refs ->
             [ref | refs]
           end)}

        other, acc2 ->
          {other, acc2}
      end)

    acc
  end

  defp walk_body(_other, _mod, acc), do: acc
end
