defmodule Mix.Tasks.Compile.Unifex do
  @moduledoc """
  Generates native boilerplate code for all the `.spec.exs` files found in `c_src` dir
  """
  use Mix.Task
  alias Unifex.{Helper, InterfaceIO, Specs, CodeGenerator}

  @impl Mix.Task
  def run(_args) do
    Helper.get_source_dir()
    |> InterfaceIO.get_interfaces_specs!()
    |> Enum.each(fn {name, dir, specs_file} ->
      codes = specs_file |> Specs.parse(name) |> CodeGenerator.generate_code()
      codes |> Enum.map(&InterfaceIO.store_interface!(name, dir, &1))
      interfaces = codes |> Enum.map(fn {_header, _source, interface} -> interface end)
      tie_header = Unifex.CodeGenerator.TieHeader.generate_tie_header(name, interfaces)
      InterfaceIO.store_tie_header!(name, dir, tie_header)
      InterfaceIO.store_gitignore!(dir)
    end)
  end
end
