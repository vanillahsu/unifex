defmodule Unifex.Specs do
  @moduledoc """
  Module that handles parsing Unifex specs for native boilerplate code generation.

  For information on how to create such specs, see `Unifex.Specs.DSL` module.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          module: module() | nil,
          functions_args: [{function_name :: atom, [arg_type :: {atom | {:list, atom}}]}],
          functions_results: [{function_name :: atom, return_type :: Macro.t()}],
          sends: {send_name :: atom, send_term_type :: Macro.t()},
          dirty_functions: [
            {{function_name :: atom, function_arity :: non_neg_integer}, :cpu | :io}
          ],
          callbacks: [{hook :: :load | :upgrade | :unload, function_name :: String.t()}],
          interface: module,
          use_state: boolean
        }

  @enforce_keys [
    :name,
    :module,
    :functions_args,
    :functions_results,
    :sends,
    :dirty_functions,
    :callbacks,
    :interface,
    :use_state
  ]

  defstruct @enforce_keys

  @doc """
  Parses Unifex specs of native functions.
  """
  @spec parse(specs_file :: Path.t(), name :: String.t()) :: t()
  def parse(specs_file, name) do
    specs_code = File.read!(specs_file)
    {_res, binds} = Code.eval_string(specs_code, [{:unifex_config__, []}], make_env(specs_file))
    config = binds |> Keyword.fetch!(:unifex_config__) |> Enum.reverse()

    {functions_args, functions_results} =
      config
      |> Keyword.get_values(:function)
      |> Enum.map(fn {name, args, results} -> {{name, args}, {name, results}} end)
      |> Enum.unzip()

    functions_results =
      Enum.flat_map(functions_results, fn {name, results} -> Enum.map(results, &{name, &1}) end)

    %__MODULE__{
      name: name,
      module: Keyword.get(config, :module),
      functions_args: functions_args,
      functions_results: functions_results,
      sends: Keyword.get_values(config, :sends),
      dirty_functions:
        config |> Keyword.get_values(:dirty_functions) |> List.flatten() |> Map.new(),
      callbacks: Keyword.get_values(config, :callbacks),
      interface: Keyword.get(config, :interface, fn -> raise "No interface specified" end),
      use_state: Keyword.get(config, :use_state, false)
    }
  end

  # Returns clear __ENV__ with proper functions/macros imported. Useful for invoking
  # user code without possibly misleading macros and aliases from the current scope,
  # while providing needed functions/macros.
  defp make_env(file) do
    {env, _binds} =
      Code.eval_quoted(
        quote do
          import Unifex.Specs.DSL
          __ENV__
        end
      )

    %Macro.Env{env | file: file}
  end
end
