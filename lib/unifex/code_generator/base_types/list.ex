defmodule Unifex.CodeGenerator.BaseTypes.List do
  @moduledoc """
  Module implementing `Unifex.CodeGenerator.BaseType` behaviour for lists.

  They are represented in the native code as arrays with sizes passed
  via separate arguments.

  Implemented both for NIF and CNode as function parameter as well as return type.
  """
  use Unifex.CodeGenerator.BaseType
  alias Unifex.CodeGenerator.BaseType

  @impl BaseType
  def generate_native_type(ctx) do
    prefix = if ctx.mode == :const, do: "const ", else: ""

    [
      "#{prefix}#{BaseType.generate_native_type(ctx.subtype, ctx.generator)}*",
      {"unsigned int", "_length"}
    ]
  end

  @impl BaseType
  def generate_initialization(name, _ctx) do
    ~g<#{name} = NULL;>
  end

  @impl BaseType
  def generate_destruction(name, ctx) do
    ~g"""
    if(#{name} != NULL) {
      for(unsigned int i = 0; i < #{name}_length; i++) {
        #{BaseType.generate_destruction(ctx.subtype, :"#{name}[i]", ctx.generator)}
      }
      unifex_free(#{name});
    }
    """
  end

  defmodule NIF do
    @moduledoc false
    use Unifex.CodeGenerator.BaseType
    alias Unifex.CodeGenerator.BaseType

    @impl BaseType
    def generate_arg_serialize(name, ctx) do
      ~g"""
      ({
        ERL_NIF_TERM list = enif_make_list(env, 0);
        for(int i = #{name}_length-1; i >= 0; i--) {
          list = enif_make_list_cell(
            env,
            #{BaseType.generate_arg_serialize(ctx.subtype, :"#{name}[i]", ctx.generator)},
            list
          );
        }
        list;
      })
      """
    end

    @impl BaseType
    def generate_arg_parse(arg, var_name, ctx) do
      elem_name = :"#{var_name}[i]"
      len_var_name = "#{var_name}_length"
      native_type = BaseType.generate_native_type(ctx.subtype, ctx.generator)
      subtype = ctx.subtype
      postproc_fun = ctx.postproc_fun
      generator = ctx.generator

      ~g"""
      ({
      int get_list_length_result = enif_get_list_length(env, #{arg}, &#{len_var_name});
      if(get_list_length_result){
        #{var_name} = enif_alloc(sizeof(#{native_type}) * #{len_var_name});

        for(unsigned int i = 0; i < #{len_var_name}; i++) {
          #{BaseType.generate_initialization(subtype, elem_name, generator)}
        }

        ERL_NIF_TERM list = #{arg};
        for(unsigned int i = 0; i < #{len_var_name}; i++) {
          ERL_NIF_TERM elem;
          enif_get_list_cell(env, list, &elem, &list);
          #{BaseType.generate_arg_parse(subtype, elem_name, ~g<elem>, postproc_fun, generator)}
        }
      }
      get_list_length_result;
      })
      """
    end
  end

  defmodule CNode do
    @moduledoc false
    use Unifex.CodeGenerator.BaseType
    alias Unifex.CodeGenerator.BaseType

    @impl BaseType
    def generate_arg_serialize(name, ctx) do
      ~g"""
      ({
        ei_x_encode_list_header(out_buff, #{name}_length);
        for(unsigned int i = 0; i < #{name}_length; i++) {
          #{BaseType.generate_arg_serialize(ctx.subtype, :"#{name}[i]", ctx.generator)}
        }
        ei_x_encode_empty_list(out_buff);
      });
      """
    end

    @impl BaseType
    def generate_arg_parse(arg, var_name, ctx) do
      elem_name = :"#{var_name}[i]"
      len_var_name = "#{var_name}_length"
      native_type = BaseType.generate_native_type(ctx.subtype, ctx.generator)
      subtype = ctx.subtype
      postproc_fun = ctx.postproc_fun
      generator = ctx.generator

      ~g"""
      ({
        int res = 1;
        int type;
        int size;
        ei_get_type(#{arg}->buff, #{arg}->index, &type, &size);
        #{len_var_name} = (unsigned int) size;
        if(type == ERL_LIST_EXT) {
          res = ei_decode_list_header(#{arg}->buff, #{arg}->index, &size);
          #{len_var_name} = (unsigned int) size;
          #{var_name} = malloc(sizeof(#{native_type}) * #{len_var_name});

          for(unsigned int i = 0; i < #{len_var_name}; i++) {
            #{BaseType.generate_initialization(subtype, elem_name, generator)}
          }

          for(unsigned int i = 0; i < #{len_var_name}; i++) {
            #{BaseType.generate_arg_parse(subtype, elem_name, arg, postproc_fun, generator)}
          }
        } else if(type == ERL_STRING_EXT) {
          char *p = malloc(sizeof(char) * #{len_var_name});
          res = ei_decode_string(#{arg}->buff, #{arg}->index, p);
          ei_x_buff buff;
          ei_x_new_with_version(&buff);
          ei_x_encode_list_header(&buff, #{len_var_name});

          for(unsigned int i = 0; i < #{len_var_name}; i++) {
            int char_value;
            if (CHAR_MIN < 0) {
              char_value = (int)p[i];
              if(char_value < 0) {
                char_value = char_value + UCHAR_MAX + 1;
              }
            } else {
              char_value = (int)p[i];
            }
            ei_x_encode_ulong(&buff, (unsigned long)char_value);
          }
          ei_x_encode_empty_list(&buff);

          int index = 0;
          int version;
          ei_decode_version(buff.buff, &index, &version);
          res = ei_get_type(buff.buff, &index, &type, &size);
          res = ei_decode_list_header(buff.buff, &index, &size);
          #{len_var_name} = (unsigned int) size;
          #{var_name} = malloc(sizeof(#{native_type}) * #{len_var_name});
          for (unsigned int i = 0; i < #{len_var_name}; i++) {
            unsigned long tmp_ulong;
            res = ei_decode_ulong(buff.buff, &index, &tmp_ulong);
            #{elem_name} = (#{native_type})tmp_ulong;
          }
        }
        res;
      })
      """
    end
  end
end
