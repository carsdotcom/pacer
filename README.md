<object data="assets/logo.png" type="image/jpeg">
  <img src="assets/PACER.png" alt="Pacer" />
</object>

  # Pacer: An Elixir Library for Dependency Graph-Based Workflows With Robust Compile Time Safety & Guarantees

  ## Motivations

  `Pacer.Workflow` is designed for complex workflows where many interdependent data points need to be
  stitched together to provide a final result, specifically workflows where each data point needs to be
  loaded and/or calculated using discrete, application-specific logic.

  To create a struct backed by Pacer.Workflow, invoke `use Pacer.Workflow` at the top of your module and use
  the `graph/1` macro, which is explained in more detail in the docs below.

  Note that when using `Pacer.Workflow`, you can pass the following options:
  #{NimbleOptions.docs(Pacer.Workflow.Options.graph_options())}

  The following is a list of the main ideas and themes underlying `Pacer.Workflow`

  #### 1. `Pacer.Workflow`s Represent Dependency Graphs Between Data Points

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


## Contributing

We welcome everyone to contribute to Pacer -- whether it is documentation updates, proposing and/or implementing new features, or contributing bugfixes. 

Please feel free to create issues on the repo if you notice any bugs or if you would like to propose new features or implementations. 

When contributing to the codebase, please:

1. Run the test suite locally with `mix test`
2. Verify Dialyzer still passes with `mix dialyzer`
3. Run `mix credo --strict`
4. Make sure your code has been formatted with `mix format`

In your PRs please provide the following detailed information as you see fit, especially for larger proposed changes:

1. What does your PR aim to do?
2. The reason/why for the changes
3. Validation and verification instructions (how can we verify that your changes are working as expected; if possible please provide one or two code samples that demonstrate the behavior)
4. Additional commentary if necessary -- tradeoffs, background context, etc.

We will try to provide responses and feedback in a timely manner. Please feel free to ping us if you have a PR or issue that has not been responded to.
