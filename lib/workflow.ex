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
  use Spark.Dsl, default_extensions: [extensions: [Pacer.Workflow.Dsl]]

  alias Pacer.Config
  alias Pacer.Workflow.Error

  require Logger
  require Pacer.Docs

  defmacro __using__(opts) do
    {batch_telemetry_options, opts} =
      Keyword.pop(
        opts,
        :batch_telemetry_options,
        quote do
          %{}
        end
      )

    {debug_mode?, opts} = Keyword.pop(opts, :debug_mode?)

    quote do
      def __config__(:batch_telemetry_options), do: unquote(batch_telemetry_options)
      def __config__(:debug_mode?), do: unquote(debug_mode?)
      def __config__(_), do: nil

      unquote(super(opts))
    end
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
        _ -> visited |> Enum.sort() |> Enum.join(", ")
      end

    raise Error, """
    Could not sort dependencies.
    The following dependencies form a cycle:

    #{message}
    """
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
