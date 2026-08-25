defmodule Pacer.Workflow.Dsl do
  defmodule Field do
    defstruct [:name, :default, :dependencies, :resolver, :virtual?, :doc, :redact?]
  end

  @field_schema [
    name: [
      type: :atom,
      required: true,
      doc: "field name"
    ],
    dependencies: [
      default: [],
      type: {:list, :atom},
      doc: """
      A list of dependencies from the graph.
      Dependencies are specified as atoms, and each dependency must
      be another field in the same graph.

      Remember that cyclical dependencies are strictly not allowed,
      so fields cannot declare dependencies on themselves nor on
      any other field that has already declared a dependency on the
      current field.

      If the `dependencies` option is not given, it defaults to an
      empty list, indicating that the field has no dependencies.
      This will be the case if the field is a constant or can be
      constructed from values already available in the environment.
      """
    ],
    doc: [
      type: :string,
      required: false,
      default: "",
      doc: """
      Allows users to document the field and provide background and/or context
      on what the field is intended to be used for, what kind of data the field
      contains, and how the data for the field is constructed.
      """
    ],
    resolver: [
      type: {:fun, 1},
      required: false,
      doc: """
      A resolver is a 1-arity function that specifies how to calculate
      the value for a field.

      The argument passed to the function will be a map that contains
      all of the field's declared dependencies.

      For example, if we have a field like this:

      ```elixir
      field(:request, resolver: &RequestHandler.resolve/1, dependencies: [:api_key, :url])
      ```

      The resolver `RequestHandler.resolve/1` would be passed a map that looks like this:
      ```elixir
      %{api_key: "<API KEY GOES HERE>", url: "https://some.endpoint.com"}
      ```

      If the field has no dependencies, the resolver will receive an empty map. Note though
      that resolvers are only required for fields with no dependencies if the field is inside
      of a batch. If your field has no dependencies and is not inside a batch, you can skip
      defining a resolver and initialize your graph struct with a value that is either constant
      or readily available where you are constructing the struct.

      The result of the resolver will be placed on the graph struct under the field's key.

      For the above, assuming a graph that looks like this:

      ```elixir
      defmodule MyGraph do
        use Pacer.Workflow

        graph do
          field(:api_key)
          field(:url)
          field(:request, resolver: &RequestHandler.resolve/1, dependencies: [:api_key, :url])
        end
      end
      ```

      Then when the `RequestHandler.resolve/1` runs an returns a value of, let's say, `%{response: "important response"}`,
      your graph struct would look like this:

      ```elixir
      %MyGraph{
        api_key: "<API KEY GOES HERE>",
        url: "https://some.endpoint.com",
        request: %{response: "important response"}
      }
      ```
      """
    ],
    default: [
      type: :any,
      default:
        quote do
          %Pacer.Workflow.FieldNotSet{}
        end,
      doc: """
      The default value for the field. If no default is given, the default value becomes
      `#Pacer.Workflow.FieldNotSet<>`.
      """
    ],
    virtual?: [
      default: false,
      type: :boolean,
      doc: """
      A virtual field is used for intermediate or transient computation steps during the workflow and becomes a
      node in the workflow's graph, but does not get returned in the results of the workflow execution.

      In other words, virtual keys will not be included in the map returned by calling `Pacer.Workflow.execute/1`.

      The intent of a virtual field is to allow a spot for intermediate and/or transient calculation steps but
      to avoid the extra memory overhead that would be associated with carrying these values downstream if, for example,
      the map returned from `Pacer.Workflow.execute/1` is stored in a long-lived process state; intermediate or transient
      values can cause unnecessary memory bloat if they are carried into process state where they are not neeeded.

      And virtual field will excluded in inspect result.
      """
    ],
    redact?: [
      default: false,
      type: :boolean,
      doc: """
      Similar to Ecto's `redact`, it will excluded in inspect  result.
      """
    ]
  ]

  @field %Spark.Dsl.Entity{
    name: :field,
    args: [:name],
    target: Field,
    schema: @field_schema,
    transform: {__MODULE__, :resolver_with_dep_graph, []}
  }

  defmodule BatchField do
    defstruct [:name, :default, :dependencies, :resolver, :virtual?, :guard, :doc, :redact?]
  end

  @batch_field_schema Keyword.merge(
                        @field_schema,
                        default: [
                          required: true,
                          type: :any,
                          doc: """
                          The default value for the field. If no default is given, the default value becomes
                          `#Pacer.Workflow.FieldNotSet<>`.
                          """
                        ],
                        resolver: [
                          required: true,
                          type: {:fun, 1},
                          doc: """
                          A guard is a 1-arity function that takes in a map with the field's dependencies and returns either true or false.
                          If the function returns `false`, it means there is no work to do and thus no reason to spin up another process
                          to run the resolver function. In this case, the field's default value is returned.
                          If the function returns `true`, the field's resolver will run in a separate process.
                          """
                        ],
                        guard: [
                          type: {:fun, 1},
                          doc: """
                          A guard is a 1-arity function that takes in a map with the field's dependencies and returns either true or false.
                          If the function returns `false`, it means there is no work to do and thus no reason to spin up another process
                          to run the resolver function. In this case, the field's default value is returned.
                          If the function returns `true`, the field's resolver will run in a separate process.
                          """
                        ]
                      )

  @batch_field %Spark.Dsl.Entity{
    name: :field,
    args: [:name],
    target: BatchField,
    schema: @batch_field_schema,
    transform: {__MODULE__, :resolver_with_dep_graph, []}
  }

  def resolver_with_dep_graph(field_entity) do
    if field_entity.dependencies != [] and is_nil(field_entity.resolver) do
      {:error,
       """
       Field #{field_entity.name} declared at least one dependency, but did not specify a resolver function.
       Any field that declares at least one dependency must also declare a resolver function.
       """}
    else
      {:ok, field_entity}
    end
  end

  defmodule Batch do
    defstruct [:name, :fields, :batch_options]
  end

  @batch_schema [
    name: [
      type: :atom,
      required: true
    ],
    batch_options: [
      type:
        {:keyword_list,
         timeout: [
           type: :non_neg_integer,
           required: false,
           default: 1000,
           doc: """
           The task that is timed out is killed and returns {:exit, :timeout}.
           This :kill_task option only exits the task process that fails and not the process that spawned the task.
           """
         ],
         on_timeout: [
           type: :atom,
           required: false,
           default: :kill_task,
           doc: """
           The time in milliseconds that the batch is allowed to run for.
           Defaults to 1,000 (1 second).
           """
         ]},
      default: [on_timeout: :kill_task, timeout: 1000]
    ]
  ]

  @batch %Spark.Dsl.Entity{
    name: :batch,
    args: [:name, :batch_options],
    target: Batch,
    schema: @batch_schema,
    entities: [fields: [@batch_field]]
  }

  @graph %Spark.Dsl.Section{
    name: :graph,
    schema: [],
    entities: [@field, @batch]
  }

  use Spark.Dsl.Extension,
    sections: [@graph],
    transformers: [Pacer.Workflow.Dsl.Transformers.CodeGeneration],
    verifiers: []

  def field_schema, do: @field_schema
  def batch_field_schema, do: @batch_field_schema
  def batch_schema, do: @batch_schema
end
