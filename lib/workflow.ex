defmodule Pacer.Workflow do
  @moduledoc """
  Dependency Graph-Based Workflows With Robust Compile Time Safety & Guarantees

  ## Motivations

  `Pacer.Workflow` is designed for complex workflows where many interdependent data points need to be
  stitched together to provide a final result, specifically workflows where each data point needs to be
  loaded and/or calculated using discrete, application-specific logic.

  To create a struct backed by Pacer.Workflow, invoke `use Pacer.Workflow` at the top of your module and use
  the `graph/1` macro, which is explained in more detail in the docs below.

  Note that when using `Pacer.Workflow`, you can pass the following options:
  #{NimbleOptions.docs(Pacer.Workflow.Options.graph_options())}

  The following is a list of the main ideas and themes underlying `Pacer.Workflow`

  #### 1. `Workflow`s Are Dependency Graphs

  `Pacer.Workflow`s are backed by dependency graphs (specifically represented as directed acyclic graphs) that are constructed at compile-time.
  Your `Workflow`s will define a set of data points, represented as `field`s (see below); each `field` must explicitly define
  the dependencies it has on other fields in the `Workflow`. For example, if we have a workflow where we load
  a set of users and then fire off some requests to a 3rd party service to fetch some advertisements for those users,
  our `Workflow` might look something like this:

  ```elixir
  defmodule UserAdsWorkflow do
    use Pacer.Workflow

    graph do
      field(:users)
      field(:user_advertisements, resolver: &Ads.fetch_user_ads/1, dependencies: [:users])
    end
  end
  ```

  Why is the dependency graph idea important here?

  In the above, simplified example with only two fields, there may not be a need to define a dependency graph
  because we can look at the two fields and immediately realize that we first need to have the set of `users`
  before we can make the call to load `:user_advertisements`.

  However, in complex workflows with dozens or even hundreds of data points, if we were to try to manage what data points
  need to be loaded in which order manually, it would be a daunting and time-consuming task. Not only that, we would also
  run the risk of getting the ordering wrong, AND/OR when new data points are added or removed in the future, that we would
  need to manually rearrange things for each data point to be loaded in the correct order.

  The result is untenable for workflows of sufficient size.

  This is where dependency graphs come in to play. By forcing you to explicitly declare the other fields that
  you depend on in the workflow, `Pacer.Workflow` can build out a dependency graph and figure out how to schedule the
  execution of each of your resolver functions (see below for more details on resolvers) so that each function
  will only be called when its dependencies are ready. That eliminates the need to manually rearrange calls in
  your codebase, and also allows you to have discrete, single-purpose resolvers that can be rigorously unit-tested
  against a known, constrained set of inputs.

  #### 2. Batched, Parallel Requests to Disparate External Systems (3rd-party APIs, Database Calls, etc.)

  `Pacer.Workflow`s also allow users to fire off potentially high-latency calls in parallel to reduce overall
  latency of a `Workflow`. To do so, we can use the `batch/2` macro inside of your `graph` definition. One caveat
  to this, however, is that _fields inside of a batch definition must not have any dependencies on other fields
  inside the same batch_.

  Batches are nice to use when a workflow has multiple high-latency requests that need to be made. Batching the
  requests together, when possible, will fire off the requests in parallel. The requests can be to disparate,
  unrelated services, APIs, and external systems including databases and/or caches.

  Note: `batch`es should not be confused with `batch loading` data in the sense that, for example, GraphQL batches
  are used where users may provide a set of ids, etc., for related entities and the batch processing loads all of or
  as many of those entities in a single request rather than making a single request per entity. `Pacer.Workflow` batches
  can be used to do so in roughly the same way, but that choice is left up to the user and the implementation.
  The key idea of a `batch` here is that you have multiple (potentially) high-latency requests that you want to execute
  together (in parallel), rather than saying "I have a set of entities that I want to load as a batch request".

  For example, if we go back to the earlier example of a user-based workflow where we load a set of users and fetch
  advertisements for those users, if we add in another request to, say, an analytics service to get some more data on
  the set of users we have just loaded, we can do that in a batch as follows:

  ```elixir
  defmodule UserAdsWorkflow do
    use Pacer.Workflow

    graph do
      field(:users)
      batch :requests do
        field(:user_advertisements, resolver: &Ads.fetch_user_ads/1, dependencies: [:users])
        field(:analytics, resolver: &Analytics.analyze_users/1, dependencies: [:users])
      end
    end
  end
  ```

  Now, rather than those two requests being fired sequentially (and thereby boosting the latency of the workflow to be
  equal to the latency of the ads request _plus_ the latency of the analytics request,
  the latency will instead be capped at the slowest of the two requests).

  #### 3. Compile-Time Safety And Guarantees

  The third motivating factor behind `Pacer.Workflow` is to provide a robust set of compile-time safety mechanisms.
  These include:
    - Detecting and preventing cyclical dependencies in the dependency graph defined by the workflow
    - Preventing "reflexive" dependencies, where a field depends on itself
    - Detecting invalid options on `field`s and `batch`es
    - Preventing a single module from defining more than one `Workflow`
    - Detecting duplicate field definitions in a graph
    - Ensuring that resolver definitions fit the contract required by `Pacer.Workflow` (a 1-arity function that takes a map)
    - Detecting dependencies on fields that do not exist in the graph definition
    - Requiring fields defined inside of a batch to have a resolver function defined

  `Pacer.Workflow` strives to provide helpful error messages to the user at compile time when it detects any issues
  and tries to direct the user on what went wrong, why, and how to fix the issue.

  The compile-time safety can prevent a whole class of issues at runtime, and also allows the dependency graph
  to be computed once at compile time. Building the dependency graph at compile time allows Pacer to cache the
  results of the graph and make those results accessible at runtime so your application does not have to incur
  the cost of building out the dependency graph at runtime.

  ## Summary

  `Pacer.Workflow` provides the ability to explicitly declare a dependency graph, where the nodes in the
  graph map to fields in a struct defined via the `graph/1` API.

  The key idea behind `Pacer.Workflow` is that it enables users to create Elixir structs that serve as containers
  of loosely-related fields, where the fields in the struct have dependencies between other fields in the struct.

  A "dependency", in the sense it is used here, means that one field relies on another field's value being readily
  available and loaded in memory before its own value can be computed or loaded. For example, if you have a struct
  `%MyStruct{field_a: 1, field_b: <field_a's value + 1>}`, `:field_b` is dependent on `:field_a`'s value already
  being present before it can be calculated.

  The example given above can be solved in a more straightforward way, by having a simple function to build out the
  entire struct given `:field_a`'s value as input, i.e.:

  ```elixir
  def build_my_struct(field_a_input) do
    %MyStruct{field_a: field_a_input, field_b: field_a_input + 1}
  end
  ```

  While conceptually simple, this pattern becomes more difficult to maintain when additional fields are added with dependencies between each other.

  `Pacer.Workflow` addresses this problem by forcing users to explicitly declare the dependencies between fields up front, at compile time.
  Once the fields and dependencies have been declared, `Pacer.Workflow` can build a dependency graph, which allows the graph to solve for
  the problem of dependency resolution by answering the question: Which fields need to be available when and in what order do they need to be executed?

  There are a few key concepts to know in order to build out a `Pacer.Workflow`-backed struct:

  ## Fields

  A field can be defined within a graph definition with the `field/2` macro. A field
  maps one-to-one to keys on the struct generated by the graph definition. Fields are
  how you explicitly declare the dependencies each field has on other fields within the
  same graph. You do this by providing a list of dependencies as atoms to the `field/2`
  macro:

    ```elixir
    graph do
      field(:field_one)
      field(:field_two)
      field(:my_dependent_field, resolver: &MyResolver.resolve/1 dependencies: [:field_one, :field_two])
    end
    ```

  If the `:dependencies` option is not given, it defaults to an empty list and effectively means
  that the field has no dependencies. This may be the case when the value for the field meets one
  of the following conditions:

    - The value is a constant
    - The value is already available and accessible in memory when creating the struct

  Fields that do explicitly declare at least one dependency MUST also pass in a `:resolver` option.
  See the [Resolvers](#resolvers) section below for more details.

  Additionally, fields may declare a default value by passing a default to the `:default` option key:

    ```elixir
    graph do
      field(:my_field, default: 42)
    end
    ```

  ## Resolvers

  Resolvers are 1-arity functions that take in the values from dependencies as input and return
  the value that should be placed on the struct key for the associated `field`. Resolvers are
  function definitions that `Pacer.Workflow` can use to incrementally compute all values needed.

  For example, for a graph definition that looks like this:

    ```elixir
    defmodule MyGraph do
      use Pacer.Workflow

      graph do
        field(:field_one)
        field(:dependent_field, resolver: &__MODULE__.resolve/1, dependencies: [:field_one])
      end

      def resolve(inputs) do
        IO.inspect(inputs.field_one, label: "Received field_one's value")
      end
    end
    ```

  Resolver functions will always be called with a map that contains the values for fields declared as dependencies.
  In the above example, that means if we have a struct `%MyGraph{field_one: 42}`, the resolver will be invoked with
  `%{field_one: 42}`.

  Keep in mind that if you declare any dependencies, you MUST also declare a resolver.


  ## Batches

  Batches can be defined using the `batch/3` macro.

  Batches allow users to group together a set of fields whose resolvers can and should be run in
  parallel. The main use-case for batches is to reduce running time for fields whose resolvers can
  have high-latencies. This generally means that batches are useful to group together calls that hit
  the network in some way.

  Batches do impose some more restrictive constraints on users, however. For example, all fields
  defined within a batch MUST NOT declare dependencies on any other field in the same batch. This
  is because the resolvers will run concurrently with one another, so there is no way to guarantee
  that a field within the same batch will have a value ready to use and pass to a separate resolver
  in the same batch. In scenarios where you find this happening, `Pacer.Workflow` will raise a compile time
  error and you will need to rearrange your batches, possibly creating two separate batches or forcing
  one field in the batch to run sequentially as a regular field outside of a `batch` block.

  Batches must also declare a name and fields within a batch must define a resolver.
  Batch names must also be unique within a single graph definition. Resolvers are required
  for fields within a batch regardless of whether or not the field has any dependencies.

  Ex.:

    ```elixir
    defmodule MyGraphWithBatches do
      use Pacer.Workflow

      graph do
        field(:regular_field)

        batch :http_requests do
          field(:request_one, resolver: &__MODULE__.resolve/1)
          field(:request_two, resolver: &__MODULE__.resolve/1, dependencies: [:regular_field])
        end

        field(:another_field, resolver: &__MODULE__.simple_resolver/1, dependencies: [:request_two])
      end

      def resolve(_) do
        IO.puts("Simulating HTTP request")
      end

      def simple_resolver(_), do: :ok
    end
    ```

  Notes:

  The order fields are defined in within a `graph` definition does not matter. For example, if you have a field `:request_one` that depends
  on another field `:request_two`, the fields can be declared in any order.

  ## Telemetry

  Pacer provides two levels of granularity for workflow telemetry: one at the entire workflow level, and one at the resolver level.

  For workflow execution, Pacer will trigger the following telemetry events:

  - `[:pacer, :workflow, :start]`
      - Measurements include: `%{system_time: integer(), monotonic_time: integer()}`
      - Metadata provided: `%{telemetry_span_context: term(), workflow: module()}`, where the `workflow` key contains the module name for the workflow being executed
  - `[:pacer, :workflow, :stop]`
     - Measurements include: `%{duration: integer(), monotonic_time: integer()}`
     - Metadata provided: `%{telemetry_span_context: term(), workflow: module()}`, where the `workflow` key contains the module name for the workflow being executed
  - `[:pacer, :workflow, :exception]`
      - Measurements include: `%{duration: integer(), monotonic_time: integer()}`
      - Metadata provided: %{kind: :throw | :error | :exit, reason: term(), stacktrace: list(), telemetry_span_context: term(), workflow: module()}, where the `workflow` key contains the module name for the workflow being executed

  At the resolver level, Pacer will trigger the following telemetry events:

  - `[:pacer, :execute_vertex, :start]`
      - Measurements and metadata similar to `:workflow` start event, with the addition of the `%{field: atom()}` value passed in metadata. The `field` is the name of the field for which the resolver is being executed.
  - `[:pacer, :execute_vertex, :stop]`
      - Measurements and metadata similar to `:workflow` stop event, with the addition of the `%{field: atom()}` value passed in metadata. The `field` is the name of the field for which the resolver is being executed.
  - `[:pacer, :execute_vertex, :exception]`
      - Measurements and metadata similar to `:workflow` exception event, with the addition of the `%{field: atom()}` value passed in metadata. The `field` is the name of the field for which the resolver is being executed.

  Additionally, for `[:pacer, :execute_vertex]` events fired on batched resolvers (which will run in parallel processes), users can provide their own metadata through configuration.

  Users may provide either a keyword list of options which will be merged into the `:execute_vertex` event metadata, or an MFA `{mod, fun, args}` tuple that points to a function which
  returns a keyword list that will be merged into the `:execute_vertex` event metadata.

  There are two routes for configuring these telemetry options for batched resolvers: in the application environment using the `:pacer, :batch_telemetry_options` config key, or
  on the individual workflow modules themselves by passing `:batch_telemetry_options` when invoking `use Pacer.Workflow`.
  Configuration defined at the workflow module will override configuration defined in the application environment.

  Here are a couple of examples:

  ### User-Provided Telemetry Metadata for Batched Resolvers in Applicaton Config
  ```elixir
  # In config.exs (or whatever env config file you want to target):

  config :pacer, :batch_telemetry_options, application_name: MyApp

  ## When you invoke a workflow with batched resolvers now, you will get `%{application_name: MyApp}` merged into your
  ## event metadata in the `[:pacer, :execute_vertex, :start | :stop | :exception]` events.
  ```

  ### User-Provided Telemetry Metadata for Batched Resolvers at the Workflow Level
  ```elixir
  defmodule MyWorkflow do
    use Pacer.Workflow, batch_telemetry_options: [extra_context: "some context from my application"]

    graph do
      field(:a)

      batch :long_running_requests do
        field(:b, dependencies: [:a], resolver: &Requests.trigger_b/1, default: nil)
        field(:c, dependencies: [:a], resolver: &Requests.trigger_c/1, default: nil)
      end
    end
  end

  ## Now when you invoke `Pacer.execute(MyWorkflow)`, you will get `%{extra_context: "some context from my application"}`
  ## merged into the metadata for the `[:pacer, :execute_vertex, :start | :stop | :exception]` events for fields `:b` and `:c`
  ```

  Note that you can also provide an MFA tuple that points to a module/function that returns a keyword list of options to be
  injected into the metadata on `:execute_vertex` telemetry events for batched resolvers. This allows users to execute code at runtime
  to inject dynamic values into the metadata. Users may use this to inject things like span_context from the top-level workflow process
  into the parallel processes that run the batch resolvers. This lets you propagate context from, i.e., a process dictionary at the top-level
  into the sub-processes:

  ```elixir
  defmodule MyApp.BatchOptions do
    def inject_context do
      [span_context: MyTracingLibrary.Tracer.current_context()]
    end
  end

  ## Use this function to inject span context by configuring it at the workflow level or in the application environment

  ## In config.exs:

  config :pacer, :batch_telemetry_options, {MyApp.BatchOptions, :inject_context, []}
  ```

  ### Using debug_mode config:

  An optional config for debug mode will log out caught errors from batch resolvers.
  This is helpful for local development as the workflow will catch the error and return
  the default to keep the workflow continuing.

  ```elixir
  defmodule MyWorkflow do
    use Pacer.Workfow, debug_mode?: true

     graph do
        field(:a, default: 1)

        batch :http_requests do
          field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a], default: :hello)
        end
      end

      def calculate_b(%{a: _a}), do: raise("OH NO")
  end
  ```
  When running the workflow above, field b will silently raise as the default
  will be returned. In debug mode, you will also get a log telling you the error
  and the default returned.

  """
  alias Pacer.Config
  alias Pacer.Workflow.Error
  alias Pacer.Workflow.FieldNotSet
  alias Pacer.Workflow.Options

  require Logger
  require Pacer.Docs

  @example_graph_message """
  Ex.:

  defmodule MyValidGraph do
    use Pacer.Workflow

    graph do
      field(:custom_field)
      field(:field_a, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
      field(:field_with_default, default: "this is a default value")

      batch :http_requests, timeout: :timer.seconds(1) do
        field(:request_1, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field], default: 5)

        field(:request_2, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field, :field_a], default: "this is the default for request2")
        field(:request_3, resolver: &__MODULE__.do_work/1, default: :this_default)
      end
    end

    def do_work(_), do: :ok
  end
  """

  @default_batch_options Options.default_batch_options()

  defmacro __using__(opts) do
    quote do
      import Pacer.Workflow,
        only: [
          graph: 1,
          batch: 2,
          batch: 3,
          field: 1,
          field: 2,
          find_cycles: 1
        ]

      alias Pacer.Workflow.Options
      require Pacer.Docs

      Module.register_attribute(__MODULE__, :pacer_generate_docs?, accumulate: false)

      generate_docs? = Keyword.get(unquote(opts), :generate_docs?, true)

      Module.put_attribute(
        __MODULE__,
        :pacer_generate_docs?,
        generate_docs?
      )

      Module.register_attribute(__MODULE__, :pacer_debug_mode?, accumulate: false)
      debug_mode? = Keyword.get(unquote(opts), :debug_mode?, false)
      Module.put_attribute(__MODULE__, :pacer_debug_mode?, debug_mode?)

      batch_telemetry_options = Keyword.get(unquote(opts), :batch_telemetry_options, %{})

      Module.put_attribute(__MODULE__, :pacer_batch_telemetry_options, batch_telemetry_options)

      Module.register_attribute(__MODULE__, :pacer_docs, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_graph_vertices, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_field_to_batch_mapping, accumulate: false)
      Module.register_attribute(__MODULE__, :pacer_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_struct_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_dependencies, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_resolvers, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_batches, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_batch_dependencies, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_batch_guard_functions, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_batch_options, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_batch_resolvers, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_vertices, accumulate: true)
      Module.register_attribute(__MODULE__, :pacer_virtual_fields, accumulate: true)
    end
  end

  @doc """
  The graph/1 macro is the main entrypoint into Pacer.Workflow to create a dependency graph struct.
  `use` the `Pacer.Workflow` macro at the top of your module and proceed to define your fields and/or batches.

  Example
  ```elixir
    defmodule MyValidGraph do
      use Pacer.Workflow

      graph do
        field(:custom_field)
        field(:field_a, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
        field(:field_with_default, default: "this is a default value")

        batch :http_requests do
          field(:request_1, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field, :field_a])
          field(:request_2, resolver: &__MODULE__.do_work/1)
        end
      end

      def do_work(_), do: :ok
    end
  ```

  Your module may only define ONE graph per module.

  The above example will also create a struct with all of the fields defined within the graph, as follows:

  ```elixir
  %MyValidGraph{
    custom_field: nil,
    field_a: nil,
    field_with_default: "this is a default value",
    request_1: nil,
    request_2: nil
  }
  ```


  The graph macro gives you access to some defined metadata functions, such as (using the above example graph):
    - `MyValidGraph.__graph__(:fields)`
    - `MyValidGraph.__graph__(:dependencies, :http_requests)`
    - `MyValidGraph.__graph__(:resolver, :field_a)`

  **Caution: These metadata functions are mostly intended for Pacer's internal use. Do not rely on their return values in runtime
  code as they may change as changes are made to the interface for Pacer.
  """
  # credo:disable-for-lines:79 Credo.Check.Refactor.ABCSize
  # credo:disable-for-lines:79 Credo.Check.Refactor.CyclomaticComplexity
  defmacro graph(do: block) do
    caller = __CALLER__

    prelude =
      quote do
        Module.put_attribute(__MODULE__, :pacer_field_to_batch_mapping, %{})

        if line = Module.get_attribute(__MODULE__, :pacer_graph_defined) do
          raise Error, """
          Module #{inspect(__MODULE__)} already defines a graph on line #{line}
          """
        end

        @pacer_graph_defined unquote(caller.line)

        @after_compile Pacer.Workflow

        unquote(block)
      end

    # credo:disable-for-lines:155 Credo.Check.Refactor.LongQuoteBlocks
    postlude =
      quote unquote: false do
        batched_dependencies =
          Enum.reduce(@pacer_batch_dependencies, %{}, fn {batch_name, _field_name, deps},
                                                         batched_dependencies ->
            Map.update(batched_dependencies, batch_name, deps, fn existing_val ->
              Enum.uniq(Enum.concat(existing_val, deps))
            end)
          end)

        batched_field_dependencies =
          Enum.reduce(@pacer_batch_dependencies, %{}, fn {_batch_name, field_name, deps},
                                                         batched_field_dependencies ->
            Map.put(batched_field_dependencies, field_name, deps)
          end)

        batched_fields =
          Enum.reduce(@pacer_batch_dependencies, %{}, fn {batch_name, field_name, _deps}, acc ->
            Map.update(acc, batch_name, [field_name], fn existing_val ->
              [field_name | existing_val]
            end)
          end)

        batched_resolvers =
          Enum.reduce(@pacer_batch_resolvers, %{}, fn {batch, field, resolver}, acc ->
            Map.update(acc, batch, [{field, resolver}], fn fields_and_resolvers ->
              [{field, resolver} | fields_and_resolvers]
            end)
          end)

        batch_guard_functions =
          Enum.reduce(@pacer_batch_guard_functions, %{}, fn {_batch, field, guard}, acc ->
            Map.put(acc, field, guard)
          end)

        @pacer_batch_dependencies
        |> Enum.reduce([], fn {batch, _, _}, batches -> [batch | batches] end)
        |> Enum.each(fn batch ->
          fields_for_batch =
            batched_fields
            |> Map.get(batch, [])
            |> MapSet.new()

          deps_for_batch =
            batched_dependencies
            |> Map.get(batch, [])
            |> MapSet.new()

          intersection = MapSet.intersection(fields_for_batch, deps_for_batch)

          unless Enum.empty?(intersection) do
            raise Error,
                  """
                  Found at least one invalid field dependency inside of a Pacer.Workflow batch.
                  Invalid dependencies: #{inspect(Enum.to_list(intersection))}
                  Graph module: #{inspect(__MODULE__)}

                  Fields that are defined within a batch MUST not have dependencies on other
                  fields in the same batch because their resolvers will run concurrently.

                  You may need to rearrange an invalid field (or fields) out of your batch
                  if the field does have a hard dependency on another field in the batch.
                  """
          end
        end)

        # Instantiate the graph with the list of vertices derived from the graph definition
        initial_graph = Graph.add_vertices(Graph.new(), @pacer_graph_vertices)

        # Build the graph edges, where edges go from dependency -> dependent field OR batch.
        # We concat together `@pacer_batch_dependencies` with `@pacer_dependencies`:
        # - `@pacer_dependencies` is a list of `{field_name, list(field_dependencies)}`
        # - `@pacer_batch_dependencies` is a list of 3-tuples: `{batch_name, field_name, list(field_dependencies)}`.
        # The dependencies of all fields defined within a batch bubble up to the batch
        # itself.
        # Batch names become vertices in the graph, but the fields under
        # a batch are not represented in the graph as vertices: they collapse into the
        # vertex for the batch. This means that there is special treatment for batches.
        # Fields not within a batch ARE represented as vertices in the graph. So building
        # edges for fields not within a batch is relatively straighforward: take each dependency
        # the field defines and draw an edge from the dependency to the field.
        # Edges for batches require that we concat the dependencies for all fields within a batch,
        # then take that list of dependencies and iterate of each dependency. The edges then
        # become `dependency -> batch`.
        # Finally, if a dependency is itself part of a batch, we have to lookup the
        # batch it belongs to. Then, instead of drawing an edge from the dependency itself
        # to the field or batch that depends on it, we draw an edge from the dependency's batch
        # to the field or batch that depends on it.
        # The `@pacer_field_to_batch_mapping` is a map with plain fields as keys and the batch they
        # belong to as values. If a field does not belong to a batch, a lookup into the `@pacer_field_to_batch_mapping`
        # will return `nil`. We use this in the case statements within the `Enum.flat_map/2` call
        # to indicate whether or not we need to replace a field with the batch it belongs to when
        # drawing the edges.
        graph_edges =
          @pacer_batch_dependencies
          |> Enum.concat(@pacer_dependencies)
          |> Enum.flat_map(fn
            {batch, field, deps} ->
              for dep <- deps do
                case Map.get(@pacer_field_to_batch_mapping, dep) do
                  nil -> Graph.Edge.new(dep, batch)
                  dependency_batch -> Graph.Edge.new(dependency_batch, batch)
                end
              end

            {field, deps} ->
              for dep <- deps do
                case Map.get(@pacer_field_to_batch_mapping, dep) do
                  nil -> Graph.Edge.new(dep, field)
                  batch -> Graph.Edge.new(batch, field)
                end
              end
          end)

        # Update the graph with the graph edges
        graph = Graph.add_edges(initial_graph, graph_edges)

        visualization = Graph.to_dot(graph)
        # Technically, the call to `topsort/1` will fail (return `false`) if
        # there are any cycles in the graph, so we can indirectly derive whether or not
        # we have any cycles based on the return value from the call to `topsort/1` below.
        # However, we want to raise and show an error message that explicitly indicates
        # what vertices of the graph form the cycle so the user can more easily find and
        # fix any cycles they may have introduced.
        _ = find_cycles(graph)

        topsort = Graph.topsort(graph)

        if @pacer_generate_docs? do
          Pacer.Docs.generate()
        end

        # The call to `topsort/1` above returns all vertices in the graph. However,
        # not every vertex in the graph is going to have work to do, which we are deriving
        # based on whether or not the vertex has an associated resolver (for a field) or
        # list of resolvers (for batches). Any vertex that has NO associated resolvers
        # gets filtered out.
        # The result of this is what gets returned from the generated `def __graph__(:evaluation_order)`
        # function definition below. We will use this to iterate through the resolvers and execute them
        # in the order returned by the topological_sort.
        vertices_with_work_to_do =
          Enum.filter(topsort, fn vertex ->
            Keyword.get(@pacer_resolvers, vertex) || Map.get(batched_resolvers, vertex)
          end)

        defstruct Enum.reverse(@pacer_struct_fields)

        def __config__(:batch_telemetry_options), do: @pacer_batch_telemetry_options
        def __config__(:debug_mode?), do: @pacer_debug_mode?
        def __config__(_), do: nil

        def __graph__(:fields), do: Enum.reverse(@pacer_fields)
        def __graph__(:dependencies), do: Enum.reverse(@pacer_dependencies)
        def __graph__(:batch_dependencies), do: Enum.reverse(@pacer_batch_dependencies)
        def __graph__(:evaluation_order), do: unquote(vertices_with_work_to_do)
        def __graph__(:virtual_fields), do: Enum.reverse(@pacer_virtual_fields)
        def __graph__(:visualization), do: unquote(visualization)

        for {name, deps} <- @pacer_dependencies do
          def __graph__(:dependencies, unquote(name)), do: unquote(deps)
        end

        for {name, deps} <- batched_field_dependencies do
          def __graph__(:batched_field_dependencies, unquote(name)), do: unquote(deps)
        end

        for {name, guard} <- batch_guard_functions do
          def __graph__(:batched_field_guard_functions, unquote(name)), do: unquote(guard)
        end

        def __graph__(:batched_field_guard_functions, _field), do: nil

        for {batch_name, batch_options} <- @pacer_batch_options do
          def __graph__(unquote(batch_name), :options), do: unquote(batch_options)
        end

        for {batch_name, deps} <- batched_dependencies do
          def __graph__(:dependencies, unquote(batch_name)), do: unquote(deps)
        end

        for {batch_name, fields} <- batched_fields do
          def __graph__(:batch_fields, unquote(batch_name)), do: unquote(fields)
        end

        for {name, resolver} <- @pacer_resolvers do
          def __graph__(:resolver, unquote(name)), do: {:field, unquote(resolver)}
        end

        for {batch_name, fields_and_resolvers} <- batched_resolvers do
          def __graph__(:resolver, unquote(batch_name)),
            do: {:batch, unquote(fields_and_resolvers)}
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  The batch/3 macro is to be invoked when grouping fields with resolvers that will run in parallel.

  Reminder:
    - The batch must be named and unique.
    - The fields within the batch must not have dependencies on one another since they will run concurrently.
    - The fields within the batch must each declare a resolver function.

  __NOTE__: In general, only batch fields whose resolvers contain potentially high-latency operations, such as network calls.

  Example
  ```elixir
    defmodule MyValidGraph do
      use Pacer.Workflow

      graph do
        field(:custom_field)

        batch :http_requests do
          field(:request_1, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
          field(:request_2, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
          field(:request_3, resolver: &__MODULE__.do_work/1)
        end
      end

      def do_work(_), do: :ok
    end
  ```

  Field options for fields defined within a batch have one minor requirement difference
  from fields not defined within a batch: batched fields MUST always define a resolver function,
  regardless of whether or not they define any dependencies.

  ## Batch Field Options
  #{NimbleOptions.docs(Options.batch_fields_definition())}

  ## Batch options
  #{NimbleOptions.docs(Options.batch_definition())}
  """
  defmacro batch(name, options \\ @default_batch_options, do: block) do
    prelude =
      quote do
        Module.put_attribute(
          __MODULE__,
          :pacer_batch_options,
          {unquote(name),
           unquote(options)
           |> Keyword.put(:on_timeout, :kill_task)
           |> Pacer.Workflow.validate_options(Options.batch_definition())}
        )

        if unquote(name) in Module.get_attribute(__MODULE__, :pacer_batches) do
          raise Error, """
          Found duplicate batch name `#{unquote(name)}` in graph module #{inspect(__MODULE__)}.
          Batch names within a single graph instance must be unique.
          """
        else
          Module.put_attribute(__MODULE__, :pacer_batches, unquote(name))
        end
      end

    postlude =
      Macro.postwalk(block, fn ast ->
        case ast do
          {:field, metadata, [field_name | args]} ->
            batched_ast =
              quote do
                {unquote(:batch), unquote(name), unquote(field_name)}
              end

            {:field, metadata, [batched_ast | args]}

          _ ->
            ast
        end
      end)

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  The field/2 macro maps fields one-to-one to keys on the struct created via the graph definition.

  Fields must be unique within a graph instance.

  ## Options:
  There are specific options that are allowed to be passed in to the field macro, as indicated below:

  #{NimbleOptions.docs(Pacer.Workflow.Options.fields_definition())}
  """
  defmacro field(name, options \\ []) do
    quote do
      Pacer.Workflow.__field__(__MODULE__, unquote(name), unquote(options))
    end
  end

  @spec __field__(module(), atom(), Keyword.t()) :: :ok | no_return()
  def __field__(module, {:batch, batch_name, field_name}, options) do
    opts = validate_options(options, Options.batch_fields_definition())

    _ =
      module
      |> Module.get_attribute(:pacer_field_to_batch_mapping)
      |> Map.put(field_name, batch_name)
      |> tap(fn mapping ->
        Module.put_attribute(module, :pacer_field_to_batch_mapping, mapping)
      end)

    Module.put_attribute(
      module,
      :pacer_batch_resolvers,
      {batch_name, field_name, Keyword.fetch!(opts, :resolver)}
    )

    Module.put_attribute(
      module,
      :pacer_docs,
      {field_name, batch_name, Keyword.get(opts, :doc, "")}
    )

    Module.put_attribute(
      module,
      :pacer_batch_dependencies,
      {batch_name, field_name, Keyword.get(opts, :dependencies, [])}
    )

    if Keyword.get(opts, :guard) && is_function(Keyword.get(opts, :guard), 1) do
      Module.put_attribute(
        module,
        :pacer_batch_guard_functions,
        {batch_name, field_name, Keyword.fetch!(opts, :guard)}
      )
    end

    put_field_attributes(module, field_name, opts)

    unless Enum.member?(Module.get_attribute(module, :pacer_graph_vertices), batch_name) do
      Module.put_attribute(module, :pacer_graph_vertices, batch_name)
    end
  end

  def __field__(module, name, options) do
    opts = validate_options(options, Options.fields_definition())

    deps = Keyword.fetch!(opts, :dependencies)
    Module.put_attribute(module, :pacer_dependencies, {name, deps})

    if Keyword.get(opts, :virtual?) do
      Module.put_attribute(module, :pacer_virtual_fields, name)
    end

    Module.put_attribute(module, :pacer_docs, {name, Keyword.get(opts, :doc, "")})

    unless deps == [] do
      register_and_validate_resolver(module, name, opts)
    end

    put_field_attributes(module, name, opts)

    Module.put_attribute(module, :pacer_graph_vertices, name)
  end

  defp put_field_attributes(module, field_name, opts) do
    :ok = ensure_no_duplicate_fields(module, field_name)

    Module.put_attribute(
      module,
      :pacer_struct_fields,
      {field_name, Keyword.get(opts, :default, %FieldNotSet{})}
    )

    Module.put_attribute(module, :pacer_fields, field_name)
  end

  @doc """
  A Depth-First Search to find where is the dependency graph cycle
  and then display the cyclic dependencies back to the developer.
  """
  @spec find_cycles(Graph.t()) :: nil
  def find_cycles(graph), do: find_cycles(graph, Graph.vertices(graph), MapSet.new())

  defp find_cycles(_, [], _visited), do: nil

  defp find_cycles(graph, [v | vs], visited) do
    if v in visited, do: cycle_found(visited)

    find_cycles(graph, Graph.out_neighbors(graph, v), MapSet.put(visited, v))
    find_cycles(graph, vs, visited)
  end

  @spec cycle_found(any()) :: no_return()
  defp cycle_found(visited) do
    message =
      case Enum.to_list(visited) do
        [reflexive_vertex] -> "Field `#{reflexive_vertex}` depends on itself."
        _ -> Enum.join(visited, ", ")
      end

    raise Error, """
    Could not sort dependencies.
    The following dependencies form a cycle:

    #{message}
    """
  end

  @spec __after_compile__(Macro.Env.t(), binary()) :: :ok | no_return()
  def __after_compile__(%{module: module} = _env, _) do
    _ = validate_dependencies(module)

    :ok
  end

  @spec ensure_no_duplicate_fields(module(), atom()) :: :ok | no_return()
  defp ensure_no_duplicate_fields(module, field_name) do
    if Enum.member?(Module.get_attribute(module, :pacer_fields), field_name) do
      raise Error, "Found duplicate field in graph instance for #{inspect(module)}: #{field_name}"
    end

    :ok
  end

  @spec register_and_validate_resolver(module(), atom(), Keyword.t()) :: :ok | no_return()
  defp register_and_validate_resolver(module, name, options) do
    case Keyword.fetch(options, :resolver) do
      {:ok, resolver} ->
        Module.put_attribute(module, :pacer_resolvers, {name, resolver})
        :ok

      :error ->
        error_message = """
        Field #{name} in #{inspect(module)} declared at least one dependency, but did not specify a resolver function.
        Any field that declares at least one dependency must also declare a resolver function.

        #{@example_graph_message}
        """

        raise Error, error_message
    end
  end

  @spec validate_options(Keyword.t(), NimbleOptions.t()) :: Keyword.t()
  def validate_options(options, schema) do
    case NimbleOptions.validate(options, schema) do
      {:ok, options} ->
        options

      {:error, %NimbleOptions.ValidationError{} = validation_error} ->
        raise Error, """
        #{Exception.message(validation_error)}

        #{@example_graph_message}
        """
    end
  end

  @spec validate_dependencies(module()) :: :ok | no_return()
  def validate_dependencies(module) do
    deps_set =
      :dependencies
      |> module.__graph__()
      |> Enum.concat(module.__graph__(:batch_dependencies))
      |> Enum.flat_map(fn
        {_, deps} -> deps
        {_, _, deps} -> deps
      end)
      |> MapSet.new()

    field_set = MapSet.new(module.__graph__(:fields))

    unless MapSet.subset?(deps_set, field_set) do
      invalid_deps = MapSet.difference(deps_set, field_set)

      raise Error,
            """
            Found at least one invalid dependency in graph definiton for #{inspect(module)}
            Invalid dependencies: #{inspect(Enum.to_list(invalid_deps))}
            """
    end

    :ok
  end

  @doc """
  Takes a struct that has been defined via the `Pacer.Workflow.graph/1` macro.
  `execute` will run/execute all of the resolvers defined in the definition of the
  `graph` macro in an order that ensures all dependencies have been met before
  the resolver runs.

  Resolvers that have been defined within batches will be executed in parallel.
  """
  @spec execute(struct() | module()) :: struct()
  def execute(workflow) when is_atom(workflow), do: execute(struct(workflow))

  def execute(%module{} = workflow) do
    :telemetry.span([:pacer, :workflow], %{workflow: module}, fn ->
      workflow_result =
        :evaluation_order
        |> module.__graph__()
        |> Enum.reduce(workflow, &execute_vertex/2)

      {Map.drop(workflow_result, module.__graph__(:virtual_fields)), %{workflow: module}}
    end)
  end

  defp execute_vertex(vertex, %module{} = workflow) do
    case module.__graph__(:resolver, vertex) do
      {:field, resolver} when is_function(resolver, 1) ->
        metadata = %{field: vertex, workflow: workflow.__struct__}
        resolver_args = Map.take(workflow, [vertex | module.__graph__(:dependencies, vertex)])

        :telemetry.span([:pacer, :execute_vertex], metadata, fn ->
          result =
            Map.put(
              workflow,
              vertex,
              resolver.(resolver_args)
            )

          {result, metadata}
        end)

      {:batch, [{field, resolver}]} ->
        metadata = %{field: field, workflow: workflow.__struct__}

        try do
          resolver_args =
            Map.take(workflow, [field | module.__graph__(:batched_field_dependencies, field)])

          :telemetry.span([:pacer, :execute_vertex], metadata, fn ->
            {Map.put(
               workflow,
               field,
               resolver.(resolver_args)
             ), metadata}
          end)
        catch
          _kind, error ->
            if module.__config__(:debug_mode?) do
              Logger.error("""
              Resolver for #{inspect(module)}.#{vertex}'s resolver returned default.
              Your resolver function failed for #{inspect(error)}.

              Returning default value of: #{inspect(Map.get(workflow, field))}
              """)
            end

            workflow
        end

      {:batch, resolvers} when is_list(resolvers) ->
        run_concurrently(%{resolvers: resolvers, vertex: vertex, workflow: workflow})
    end
  end

  defp run_concurrently(%{resolvers: resolvers, vertex: vertex, workflow: %module{} = workflow}) do
    task_options = module.__graph__(vertex, :options)

    parent_pid = self()

    user_provided_metadata = Config.fetch_batch_telemetry_options(module)

    resolvers
    |> filter_guarded_resolvers(workflow)
    |> Enum.map(fn {field, resolver} ->
      dependencies = module.__graph__(:batched_field_dependencies, field)
      # We want to also pass the current value (which is the default) of the field itself,
      # so that we can use it in the fallback clause
      partial_workflow = Map.take(workflow, [field | dependencies])
      {field, partial_workflow, resolver}
    end)
    |> Task.async_stream(
      fn {field, partial_workflow, resolver} ->
        metadata =
          %{
            field: field,
            workflow: module,
            parent_pid: parent_pid
          }
          |> Map.merge(user_provided_metadata)

        try do
          :telemetry.span(
            [:pacer, :execute_vertex],
            metadata,
            fn ->
              {{field, resolver.(partial_workflow)},
               Map.merge(%{parent_pid: parent_pid}, user_provided_metadata)}
            end
          )
        catch
          _kind, _error ->
            {field, Map.get(partial_workflow, field)}
        end
      end,
      task_options
    )
    |> Enum.reduce(workflow, fn result, workflow ->
      case result do
        {:ok, {field, resolver_result}} ->
          Map.put(workflow, field, resolver_result)

        _ ->
          workflow
      end
    end)
  end

  defp filter_guarded_resolvers(resolvers, %module{} = workflow) do
    Enum.filter(resolvers, fn {field, _resolver} ->
      case module.__graph__(:batched_field_guard_functions, field) do
        guard_function when is_function(guard_function, 1) ->
          dependencies = module.__graph__(:batched_field_dependencies, field)

          guard_function.(Map.take(workflow, [field | dependencies]))

        _ ->
          true
      end
    end)
  end
end
