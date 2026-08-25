defmodule Pacer.Workflow.Dsl.Transformers.CodeGeneration do
  use Spark.Dsl.Transformer

  @init_info %{
    pacer_graph_vertices: [],
    pacer_field_to_batch_mapping: %{},
    pacer_docs: [],
    pacer_batches: [],
    pacer_batch_dependencies: [],
    pacer_batch_resolvers: [],
    pacer_batch_guard_functions: [],
    pacer_batch_options: [],
    pacer_struct_fields: [],
    pacer_dependencies: [],
    pacer_virtual_fields: [],
    pacer_redact_fields: [],
    pacer_resolvers: []
  }

  defp collect_field_info(field, info, batch \\ nil) do
    info =
      info
      |> update_in([:pacer_dependencies], fn v ->
        if(is_nil(batch), do: [{field.name, field.dependencies} | v], else: v)
      end)
      |> update_in([:pacer_docs], &[{field.name, field.doc} | &1])
      |> update_in([:pacer_resolvers], &[{field.name, field.resolver} | &1])
      |> update_in([:pacer_struct_fields], &[{field.name, field.default} | &1])
      |> update_in([:pacer_fields], &[field.name | &1])
      |> update_in([:pacer_graph_vertices], fn v ->
        if is_nil(batch), do: [field.name | v], else: v
      end)
      |> update_in([:pacer_virtual_fields], fn v ->
        if field.virtual?, do: [field.name | v], else: v
      end)
      |> update_in([:pacer_redact_fields], fn v ->
        if field.redact?, do: [field.name | v], else: v
      end)

    if not is_nil(batch) do
      info
      |> update_in([:pacer_field_to_batch_mapping, field.name], fn _ -> batch.name end)
      |> update_in(
        [:pacer_batch_resolvers],
        &[{batch.name, field.name, field.resolver} | &1]
      )
      |> update_in(
        [:pacer_batch_dependencies],
        &[{batch.name, field.name, field.dependencies} | &1]
      )
      |> update_in([:pacer_batch_guard_functions], fn v ->
        if is_function(field.guard, 1), do: [{field.name, field.guard} | v], else: v
      end)
    else
      info
    end
  end

  defp collect_batch_info(batch, info) do
    info
    |> update_in([:pacer_batches], &[batch.name | &1])
    |> update_in([:pacer_batch_options], &[{batch.name, batch.batch_options} | &1])
    |> update_in([:pacer_graph_vertices], fn v ->
      if batch.name not in v, do: [batch.name | v], else: v
    end)
  end

  def transform(dsl_state) do
    entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:graph])

    info =
      for entity <- entities, reduce: @init_info do
        info ->
          case entity do
            %Pacer.Workflow.Dsl.Field{} = field ->
              collect_field_info(field, info)

            %Pacer.Workflow.Dsl.Batch{} = batch ->
              for field <- batch.fields, reduce: collect_batch_info(batch, info) do
                info -> collect_field_info(field, info, batch)
              end
          end
      end

    # Instantiate the graph with the list of vertices derived from the graph definition
    initial_graph = Graph.add_vertices(Graph.new(), info.pacer_graph_vertices)

    graph_edges =
      info.pacer_batch_dependencies
      |> Enum.concat(info.pacer_dependencies)
      |> Enum.flat_map(fn
        {batch, _field, deps} ->
          for dep <- deps do
            case Map.get(info.pacer_field_to_batch_mapping, dep) do
              nil -> Graph.Edge.new(dep, batch)
              dependency_batch -> Graph.Edge.new(dependency_batch, batch)
            end
          end

        {field, deps} ->
          for dep <- deps do
            case Map.get(info.pacer_field_to_batch_mapping, dep) do
              nil -> Graph.Edge.new(dep, field)
              batch -> Graph.Edge.new(batch, field)
            end
          end
      end)

    graph = Graph.add_edges(initial_graph, graph_edges)
    _ = Pacer.Workflow.find_cycles(graph)

    visualization = Graph.to_dot(graph)

    topsort = Graph.topsort(graph)

    batched_dependencies =
      Enum.reduce(info.pacer_batch_dependencies, %{}, fn {batch_name, _field_name, deps},
                                                         batched_dependencies ->
        Map.update(batched_dependencies, batch_name, deps, fn existing_val ->
          Enum.uniq(Enum.concat(existing_val, deps))
        end)
      end)

    batched_field_dependencies =
      Enum.reduce(info.pacer_batch_dependencies, %{}, fn {_batch_name, field_name, deps},
                                                         batched_field_dependencies ->
        Map.put(batched_field_dependencies, field_name, deps)
      end)

    batched_fields =
      Enum.reduce(info.pacer_batch_dependencies, %{}, fn {batch_name, field_name, _deps}, acc ->
        Map.update(acc, batch_name, [field_name], fn existing_val ->
          [field_name | existing_val]
        end)
      end)

    batched_resolvers =
      Enum.reduce(info.pacer_batch_resolvers, %{}, fn {batch, field, resolver}, acc ->
        Map.update(acc, batch, [{field, resolver}], fn fields_and_resolvers ->
          [{field, resolver} | fields_and_resolvers]
        end)
      end)

    vertices_with_work_to_do =
      Enum.filter(topsort, fn vertex ->
        Keyword.get(info.pacer_resolvers, vertex) || Map.get(batched_resolvers, vertex)
      end)

    defstruct_ast =
      quote do
        @derive {Inspect, except: unquote(info.pacer_virtual_fields ++ info.pacer_redact_fields)}
        defstruct unquote(Enum.reverse(info.pacer_struct_fields))
      end

    graph_fun_dependencies_ast =
      for {name, deps} <- info.pacer_dependencies do
        quote do
          def __graph__(:dependencies, unquote(name)), do: unquote(deps)
        end
      end

    graph_fun_batched_field_dependencies_ast =
      for {name, deps} <- batched_field_dependencies do
        quote do
          def __graph__(:batched_field_dependencies, unquote(name)), do: unquote(deps)
        end
      end

    graph_fun_batch_guard_functions_ast =
      for {name, guard} <- info.pacer_batch_guard_functions do
        quote do
          def __graph__(:batched_field_guard_functions, unquote(name)), do: unquote(guard)
        end
      end

    graph_fun_batch_options_ast =
      for {batch_name, batch_options} <- info.pacer_batch_options do
        quote do
          def __graph__(unquote(batch_name), :options), do: unquote(batch_options)
        end
      end

    graph_fun_batched_dependencies_ast =
      for {batch_name, batch_options} <- batched_dependencies do
        quote do
          def __graph__(:dependencies, unquote(batch_name)), do: unquote(batch_options)
        end
      end

    graph_fun_batched_fields_ast =
      for {batch_name, fields} <- batched_fields do
        quote do
          def __graph__(:batch_fields, unquote(batch_name)), do: unquote(fields)
        end
      end

    graph_fun_pacer_resolvers_ast =
      for {name, resolver} <- info.pacer_resolvers do
        quote do
          def __graph__(:resolver, unquote(name)), do: {:field, unquote(resolver)}
        end
      end

    graph_fun_fields_and_resolvers_ast =
      for {batch_name, fields_and_resolvers} <- batched_resolvers do
        quote do
          def __graph__(:resolver, unquote(batch_name)),
            do: {:batch, unquote(fields_and_resolvers)}
        end
      end

    graph_fun_ast =
      quote do
        def __graph__(:fields), do: unquote(Enum.reverse(Keyword.keys(info.pacer_struct_fields)))
        def __graph__(:dependencies), do: unquote(Enum.reverse(info.pacer_dependencies))

        def __graph__(:batch_dependencies) do
          unquote(Macro.escape(Enum.reverse(info.pacer_batch_dependencies)))
        end

        def __graph__(:evaluation_order), do: unquote(vertices_with_work_to_do)
        def __graph__(:virtual_fields), do: unquote(Enum.reverse(info.pacer_virtual_fields))
        def __graph__(:visualization), do: unquote(visualization)

        unquote_splicing(graph_fun_dependencies_ast)
        unquote_splicing(graph_fun_batched_field_dependencies_ast)
        unquote_splicing(graph_fun_batch_guard_functions_ast)
        def __graph__(:batched_field_guard_functions, _field), do: nil
        unquote_splicing(graph_fun_batch_options_ast)
        unquote_splicing(graph_fun_batched_dependencies_ast)
        unquote_splicing(graph_fun_batched_fields_ast)
        unquote_splicing(graph_fun_pacer_resolvers_ast)
        unquote_splicing(graph_fun_fields_and_resolvers_ast)
      end

    ast =
      quote do
        unquote(defstruct_ast)
        unquote(graph_fun_ast)
      end

    duplicated_field = duplicated_element(info.pacer_struct_fields, &elem(&1, 0))
    duplicated_batch = duplicated_element(info.pacer_batches, &Function.identity/1)

    invalid_dependencies =
      invalid_dependencies(
        info.pacer_struct_fields,
        info.pacer_dependencies,
        info.pacer_batch_dependencies
      )

    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)

    # Transformers is run before verifiers, if here puts checkings to verifier,
    # it will still generate code and cause some warning, e.g. duplicate key `:key` found in struct.
    cond do
      not is_nil(duplicated_field) ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "Found duplicate field in graph instance for #{inspect(module)}: #{duplicated_field}",
           path: [:graph, duplicated_field],
           module: module
         )}

      not is_nil(duplicated_batch) ->
        {:error,
         Spark.Error.DslError.exception(
           message: """
           Found duplicated batch name `#{duplicated_batch}` in graph module #{inspect(module)}.
           Batch names within a single graph instance must be unique.
           """,
           path: [:graph, :batch, duplicated_batch],
           module: module
         )}

      not Enum.empty?(invalid_dependencies) ->
        {:error,
         Spark.Error.DslError.exception(
           message: """
           Found at least one invalid dependency in graph definiton for #{inspect(module)}
           Invalid dependencies: #{inspect(invalid_dependencies)}
           """,
           path: [:graph],
           module: module
         )}

      true ->
        {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], ast)}
    end
  rescue
    e in Pacer.Workflow.Error ->
      {:error,
       Spark.Error.DslError.exception(
         message: e.message,
         path: [:graph],
         module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
       )}
  end

  defp duplicated_element(kw, getter) do
    kw
    |> Enum.frequencies_by(&getter.(&1))
    |> Stream.filter(fn {_, freq} -> freq > 1 end)
    |> Enum.take(1)
    |> case do
      [] -> nil
      [{k, _}] -> k
    end
  end

  defp invalid_dependencies(struct_fields, field_deps, batch_deps) do
    struct_field_names = Keyword.keys(struct_fields)

    Enum.filter(
      Enum.flat_map(field_deps, fn {_, deps} -> deps end) ++
        Enum.flat_map(batch_deps, fn {_, _, deps} -> deps end),
      fn dep -> dep not in struct_field_names end
    )
    |> Enum.uniq()
  end
end
