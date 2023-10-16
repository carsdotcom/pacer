defmodule Pacer.WorkflowTest do
  use ExUnit.Case, async: true

  alias Pacer.Workflow.Error
  alias Pacer.Workflow.FieldNotSet

  defmodule TestGraph do
    use Pacer.Workflow

    graph do
      field(:custom_field)
      field(:field_a, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
      field(:field_with_default, virtual?: true, default: "this is a default value")

      batch :http_requests do
        field(:request_1,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:custom_field],
          default: 2
        )

        field(:request_2,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:custom_field, :field_a],
          default: "this is a default value for request2"
        )
      end
    end

    def do_work(_), do: :ok
  end

  defmodule Resolvers do
    def resolve(_), do: :ok
  end

  @valid_graph_example """
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

  describe "telemetry" do
    test "execute/1 emits a [:pacer, :workflow, :start] and [:pacer, :workflow, :stop] event" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:pacer, :workflow, :start],
          [:pacer, :workflow, :stop]
        ])

      Pacer.Workflow.execute(TestGraph)

      assert_received {[:pacer, :workflow, :start], ^ref, _, %{workflow: TestGraph}}
      assert_received {[:pacer, :workflow, :stop], ^ref, _, %{workflow: TestGraph}}
    end

    defmodule RaisingWorkflow do
      use Pacer.Workflow

      graph do
        field(:a, default: :ok)
        field(:exception_field, resolver: &__MODULE__.exception_raise/1, dependencies: [:a])
      end

      def exception_raise(_args), do: raise("oops")
    end

    test "execute/1 emits a [:pacer, :workflow, :exception] event when the workflow execution raises" do
      ref = :telemetry_test.attach_event_handlers(self(), [[:pacer, :workflow, :exception]])

      assert_raise(RuntimeError, fn ->
        Pacer.Workflow.execute(RaisingWorkflow)
      end)

      assert_received {[:pacer, :workflow, :exception], ^ref, _, %{workflow: RaisingWorkflow}}
    end
  end

  test "graph metadata" do
    assert TestGraph.__graph__(:fields) == [
             :custom_field,
             :field_a,
             :field_with_default,
             :request_1,
             :request_2
           ]
  end

  test "dependency metadata" do
    assert TestGraph.__graph__(:dependencies, :field_a) == [:custom_field]
    assert TestGraph.__graph__(:dependencies, :http_requests) == [:custom_field, :field_a]
  end

  test "virtual field metadata" do
    assert TestGraph.__graph__(:virtual_fields) == [:field_with_default]
  end

  test "batch field dependency metadata" do
    assert TestGraph.__graph__(:batched_field_dependencies, :request_1) == [:custom_field]

    assert TestGraph.__graph__(:batched_field_dependencies, :request_2) == [
             :custom_field,
             :field_a
           ]
  end

  test "batch metadata" do
    assert TestGraph.__graph__(:batch_fields, :http_requests) == [:request_1, :request_2]

    assert TestGraph.__graph__(:http_requests, :options) == [
             on_timeout: :kill_task,
             timeout: :timer.seconds(1)
           ]
  end

  test "batch options metadata with overrides" do
    defmodule BatchWithOptionOverrides do
      use Pacer.Workflow

      graph do
        field(:a)

        batch :requests, timeout: :timer.seconds(3) do
          field(:b, resolver: &__MODULE__.resolve/1, default: "default here")
        end
      end

      def resolve(_), do: :ok
    end

    assert BatchWithOptionOverrides.__graph__(:requests, :options) == [
             on_timeout: :kill_task,
             timeout: :timer.seconds(3)
           ]
  end

  test "resolver metadata" do
    {:field, field_resolver} = TestGraph.__graph__(:resolver, :field_a)

    assert is_function(field_resolver, 1),
           "Expected resolver for field_a to be a 1-arity function"

    {:batch, batch_resolvers} = TestGraph.__graph__(:resolver, :http_requests)

    assert Enum.count(batch_resolvers) == 2,
           "Expected http_requests batch node to have 2 resolvers. Got #{inspect(batch_resolvers)}"

    Enum.each(batch_resolvers, fn {field_name, resolver} ->
      assert field_name in [:request_1, :request_2]
      assert is_function(resolver, 1)
    end)
  end

  test "evaluation_order returns all nodes in the graph with work to do in topologically sorted order" do
    [:field_a, :http_requests] = TestGraph.__graph__(:evaluation_order)
  end

  test "virtual fields are not returned in the results of Pacer.Workflow.execute/1" do
    assert %TestGraph{} = result = Pacer.Workflow.execute(TestGraph)

    refute Map.has_key?(result, :field_with_default)
  end

  test "field defaults" do
    assert %TestGraph{
             field_a: %FieldNotSet{},
             custom_field: %FieldNotSet{},
             request_1: 2,
             request_2: "this is a default value for request2",
             field_with_default: "this is a default value"
           } == %TestGraph{}
  end

  describe "cycle detection" do
    test "detects cycles in a graph definition" do
      module = """
      defmodule GraphWithCycles do
        use Pacer.Workflow

        graph do
          field(:a, resolver: &__MODULE__.resolve/1, dependencies: [:b])
          field(:b, resolver: &__MODULE__.resolve/1, dependencies: [:a])
          field(:c)
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      Could not sort dependencies.
      The following dependencies form a cycle:

      a, b
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "detects reflexive cycles" do
      module = """
      defmodule GraphWithReflexiveCycle do
        use Pacer.Workflow

        graph do
          field(:a, resolver: &__MODULE__.resolve/1, dependencies: [:a])
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      Could not sort dependencies.
      The following dependencies form a cycle:

      Field `a` depends on itself.
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end
  end

  describe "graph validations" do
    test "options validations" do
      module = """
      defmodule AllTheOptionsTooManyOptions do
        use Pacer.Workflow

        graph do
          field(:a, not_an_option: &Resolvers.resolve/1, invalid_option_again: :ohno)
        end
      end
      """

      expected_error_message = """
      unknown options [:not_an_option, :invalid_option_again], valid options are: [:dependencies, :doc, :resolver, :default, :virtual?]

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "only one graph definition is allowed per module" do
      module = """
      defmodule TwoGraphs do
        use Pacer.Workflow

        graph do
          field(:a)
        end

        graph do
          field(:b)
        end
      end
      """

      expected_error_message = """
      Module TwoGraphs already defines a graph on line 4
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "fields must be unique within a graph instance" do
      module = """
      defmodule GraphWithDuplicateFields do
        use Pacer.Workflow

        graph do
          field(:a)
          field(:a)
        end
      end
      """

      expected_error_message =
        "Found duplicate field in graph instance for GraphWithDuplicateFields: a"

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "dependencies must be a list if declared" do
      module = """
      defmodule GraphWithBadDependencyField do
        use Pacer.Workflow

        graph do
          field(:a, resolver: &__MODULE__.resolve/1, dependencies: "strings are not valid values for dependencies")
          field(:b)
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      invalid value for :dependencies option: expected list, got: "strings are not valid values for dependencies"

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "dependencies must be a list of atoms when declared and non-empty" do
      module = """
      defmodule GraphWithStringsInDependencyList do
        use Pacer.Workflow

        graph do
          field(:a, resolver: &__MODULE__.resolve/1, dependencies: [:b, "strings", "are", "not", "valid", "here"])
          field(:b, default: :ok)
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      invalid list in :dependencies option: invalid value for list element at position 1: expected atom, got: "strings"

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "requires resolver functions to be a 1-arity function" do
      module = """
      defmodule GraphWithBadValueForResolver do
        use Pacer.Workflow

        graph do
          field(:a, resolver: fn -> "0-arity functions are not valid resolvers" end, dependencies: [:b])
          field(:b)
        end
      end
      """

      expected_error_message = """
      invalid value for :resolver option: expected function of arity 1, got: function of arity 0

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "requires a resolver function for any field that declares dependencies" do
      module = """
      defmodule NoResolverWithDepGraph do
        use Pacer.Workflow

        graph do
          field(:a, dependencies: [:b])
          field(:b)
        end
      end
      """

      expected_error_message = """
      Field a in NoResolverWithDepGraph declared at least one dependency, but did not specify a resolver function.
      Any field that declares at least one dependency must also declare a resolver function.

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "does not allow dependencies that are not also fields in the graph" do
      module = """
      defmodule BadGraph do
        use Pacer.Workflow

        graph do
          field(:a, resolver: &__MODULE__.resolve/1, dependencies: [:not_a_field_in_this_graph])
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      Found at least one invalid dependency in graph definiton for BadGraph
      Invalid dependencies: [:not_a_field_in_this_graph]
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end
  end

  describe "batch validations" do
    test "batch fields must define a 1-arity function as resolver" do
      module = """
      defmodule BatchFieldWithInvalidResolverValue do
        use Pacer.Workflow

        graph do
          batch :requests do
            field(:a, resolver: "this is not valid", default: 5)
          end
        end
      end
      """

      expected_error_message = """
      invalid value for :resolver option: expected function of arity 1, got: "this is not valid"

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "batch options validations" do
      module = """
      defmodule BatchAllTheOptionsTooManyOptions do
        use Pacer.Workflow

        graph do
          field(:a, default: 1)
          batch :requests, invalid_option: :ohno, not_an_option: &Resolvers.resolve/1, timeout: 1000000, exit: :brutal_kill do
            field(:y, resolver: &Resolvers.resolve/1, dependencies: [:a])
            field(:z, resolver: &Resolvers.resolve/1, dependencies: [:a])
          end
        end
      end
      """

      expected_error_message = """
      unknown options [:invalid_option, :not_an_option, :exit], valid options are: [:on_timeout, :timeout]

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "a field inside of a batch cannot have a dependency on a field in the same batch" do
      module = """
      defmodule BatchFieldDepOnSameBatch do
        use Pacer.Workflow

        graph do
          batch :requests do
            field(:a, resolver: &__MODULE__.resolve/1, dependencies: [:b], default: 12)
            field(:b, resolver: &__MODULE__.resolve/1, dependencies: [:c], default: 3)
          end
          field(:c)
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      Found at least one invalid field dependency inside of a Pacer.Workflow batch.
      Invalid dependencies: [:b]
      Graph module: BatchFieldDepOnSameBatch

      Fields that are defined within a batch MUST not have dependencies on other
      fields in the same batch because their resolvers will run concurrently.

      You may need to rearrange an invalid field (or fields) out of your batch
      if the field does have a hard dependency on another field in the batch.
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "fields cannot be duplicated within a batch" do
      module = """
      defmodule GraphWithDuplicateFieldsInBatch do
        use Pacer.Workflow

        graph do
          batch :requests do
            field(:a, resolver: &Resolvers.resolve/1, dependencies: [:b], default: :ok)
            field(:a, resolver: &Resolvers.resolve/1, dependencies: [:b], default: 123)
          end
          field(:b)
        end
      end
      """

      expected_error_message =
        "Found duplicate field in graph instance for GraphWithDuplicateFieldsInBatch: a"

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "dependencies for fields inside of a batch must be other valid fields in the graph outside of the same batch" do
      module = """
      defmodule InvalidDepInsideOfBatch do
        use Pacer.Workflow

        graph do
          batch :requests do
            field(:a, resolver: &Resolvers.resolve/1, dependencies: [:this_field_does_not_exist], default: 12)
          end
        end
      end
      """

      expected_error_message = """
      Found at least one invalid dependency in graph definiton for InvalidDepInsideOfBatch
      Invalid dependencies: [:this_field_does_not_exist]
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "fields inside of a batch MUST define a resolver, even if the field has no dependencies" do
      module = """
      defmodule BatchWithResolverlessField do
        use Pacer.Workflow

        graph do
          batch :requests do
            field(:a)
          end
        end
      end
      """

      expected_error_message = """
      required :resolver option not found, received options: [:dependencies]

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "duplicate batch names are not allowed" do
      module = """
      defmodule DuplicateBatchNameGraph do
        use Pacer.Workflow

        graph do
          batch :dupe do
            field(:a, resolver: &Resolvers.resolve/1, default: :ok)
          end

          batch :dupe do
            field(:b, resolver: &Resolvers.resolve/1, default: :ok)
          end
        end
      end
      """

      expected_error_message = """
      Found duplicate batch name `dupe` in graph module DuplicateBatchNameGraph.
      Batch names within a single graph instance must be unique.
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end

    test "fields inside of a batch MUST define a default" do
      module = """
      defmodule BatchFieldWithoutDefaultValue do
        use Pacer.Workflow

        graph do
          field(:a, default: 5)
          batch :requests do
            field(:c, resolver: &__MODULE__.resolve/1, dependencies: [:a])
          end
        end

        def resolve(_), do: :ok
      end
      """

      expected_error_message = """
      required :default option not found, received options: [:resolver, :dependencies]

      #{@valid_graph_example}
      """

      assert_raise Error, expected_error_message, fn ->
        Code.eval_string(module)
      end
    end
  end

  describe "execute/1, no batches" do
    defmodule TheTestWorkflow do
      use Pacer.Workflow

      graph do
        field(:a, default: 1)
        field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a])
      end

      def calculate_b(%{a: a}), do: a + 1
    end

    test "runs each resolver and places the results of each resolver on the associated struct field" do
      assert %TheTestWorkflow{a: 1, b: 2} == Pacer.Workflow.execute(%TheTestWorkflow{})
    end

    test "when given just the module name of a workflow, executes the workflow as if it were given an empty struct" do
      assert Pacer.Workflow.execute(TheTestWorkflow) == Pacer.Workflow.execute(%TheTestWorkflow{})
    end

    test "runs each resolver with the values set on each dependent key, even when not pulling from defaults" do
      assert %TheTestWorkflow{a: 2, b: 3} == Pacer.Workflow.execute(%TheTestWorkflow{a: 2})
    end

    defmodule NoBatchWorkflowWithResolverFailure do
      use Pacer.Workflow

      graph do
        field(:a, default: 1)
        field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a])
      end

      def calculate_b(%{a: _a}), do: raise("OH NO")
    end

    test "when field's resolver raises, exits" do
      assert_raise RuntimeError, fn ->
        Pacer.Workflow.execute(%NoBatchWorkflowWithResolverFailure{})
      end
    end
  end

  describe "execute/1 with batches" do
    defmodule TestWorkflowWithSingleBasicBatch do
      use Pacer.Workflow

      graph do
        field(:a, default: "the start")

        batch :requests do
          field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a], default: "here in b")
          field(:c, resolver: &__MODULE__.calculate_c/1, dependencies: [:a], default: "here in c")
        end
      end

      def calculate_b(%{a: a}), do: a <> " plus b"
      def calculate_c(%{a: a}), do: a <> " plus c"
    end

    test "runs batched resolvers and puts the results on the associated keys" do
      assert %TestWorkflowWithSingleBasicBatch{
               a: "the start",
               b: "the start plus b",
               c: "the start plus c"
             } == Pacer.Workflow.execute(%TestWorkflowWithSingleBasicBatch{})
    end

    defmodule TestWorkflowWithSingleBasicBatchAndQuickTimeout do
      use Pacer.Workflow

      graph do
        field(:a, default: "the start")

        batch :requests, timeout: 10 do
          field(:b,
            resolver: &__MODULE__.calculate_b/1,
            dependencies: [:a],
            default: "timed out so here in b"
          )

          field(:c,
            resolver: &__MODULE__.calculate_c/1,
            dependencies: [:a],
            default: "timed out so here in c"
          )
        end
      end

      def calculate_b(%{a: a}) do
        Process.sleep(1000)
        a <> " plus b"
      end

      def calculate_c(%{a: a}) do
        Process.sleep(1000)
        a <> " plus c"
      end
    end

    test "when batch field resolvers time out, return the defaults" do
      assert %TestWorkflowWithSingleBasicBatchAndQuickTimeout{
               a: "the start",
               b: "timed out so here in b",
               c: "timed out so here in c"
             } == Pacer.Workflow.execute(%TestWorkflowWithSingleBasicBatchAndQuickTimeout{})
    end

    defmodule WorkflowWithSingleFieldBatch do
      use Pacer.Workflow

      graph do
        field(:a, default: 1)

        batch :requests do
          field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a], default: 4)
        end
      end

      def calculate_b(%{a: a}) do
        send(self(), :calculating_b)
        a + 2
      end
    end

    test "a batch with a single field runs in the same process as the caller" do
      assert %WorkflowWithSingleFieldBatch{
               a: 1,
               b: 3
             } == Pacer.Workflow.execute(%WorkflowWithSingleFieldBatch{})

      assert_received :calculating_b
    end

    defmodule WorkflowWithTwoBatches do
      use Pacer.Workflow

      graph do
        field(:a, default: "the start")
        field(:b, default: "the end")

        batch :one do
          field(:c,
            resolver: &__MODULE__.batch_one_resolver/1,
            dependencies: [:a],
            default: "here in c"
          )

          field(:d,
            resolver: &__MODULE__.batch_one_resolver/1,
            dependencies: [:a],
            default: "here in d"
          )
        end

        batch :two do
          field(:e,
            resolver: &__MODULE__.batch_two_resolver/1,
            dependencies: [:b],
            default: "here in e"
          )

          field(:f,
            resolver: &__MODULE__.batch_two_resolver/1,
            dependencies: [:b],
            default: "here in f"
          )
        end
      end

      def batch_one_resolver(%{a: a}), do: a <> " plus a batch one resolver"
      def batch_two_resolver(%{b: b}), do: "a batch two resolver plus " <> b
    end

    test "with multiple batches, evaluates each resolver within batches and places the results on the associated keys" do
      assert %WorkflowWithTwoBatches{
               a: "the start",
               b: "the end",
               c: "the start plus a batch one resolver",
               d: "the start plus a batch one resolver",
               e: "a batch two resolver plus the end",
               f: "a batch two resolver plus the end"
             } == Pacer.Workflow.execute(%WorkflowWithTwoBatches{})
    end

    defmodule BatchWorkflowWithResolverFailure do
      use Pacer.Workflow

      graph do
        field(:a, default: 1)

        batch :requests do
          field(:b, resolver: &__MODULE__.calculate_b/1, dependencies: [:a], default: 6)
        end
      end

      def calculate_b(%{a: _a}), do: raise("OH NO")
    end

    test "when batch field's resolver raises, returns default" do
      assert %BatchWorkflowWithResolverFailure{a: 1, b: 6} ==
               Pacer.Workflow.execute(%BatchWorkflowWithResolverFailure{})
    end

    defmodule BatchWorkflowWithMultipleResolverIssues do
      use Pacer.Workflow

      graph do
        field(:a, default: 1)

        batch :requests, timeout: 1000 do
          field(:b,
            resolver: &__MODULE__.calculate_b/1,
            dependencies: [:a],
            default: "ddddefault"
          )

          field(:c,
            resolver: &__MODULE__.calculate_c/1,
            dependencies: [:a],
            default: "timed out so default here for c"
          )

          field(:d,
            resolver: &__MODULE__.calculate_d/1,
            dependencies: [:a],
            default: 6
          )
        end
      end

      def calculate_b(%{a: _a}), do: raise("OH NO")

      def calculate_c(%{a: _a}) do
        Process.sleep(1500)
        "cccccc"
      end

      def calculate_d(%{a: a}), do: a + 23
    end

    test "all sorts of batch issues, but returns defaults and or resolved results" do
      assert %BatchWorkflowWithMultipleResolverIssues{
               a: 1,
               b: "ddddefault",
               c: "timed out so default here for c",
               d: 24
             } ==
               Pacer.Workflow.execute(%BatchWorkflowWithMultipleResolverIssues{})
    end
  end

  describe "batch field guards" do
    defmodule BatchWorkflowWithGuard do
      use Pacer.Workflow

      graph do
        field(:need_to_do_more_work?)
        field(:other_field)
        field(:test_pid)

        batch :test_batch do
          field(:no_guard_field,
            resolver: &__MODULE__.send_message/1,
            dependencies: [:other_field, :test_pid],
            default: :ok
          )

          field(:guard_field,
            resolver: &__MODULE__.send_message/1,
            guard: &__MODULE__.should_execute?/1,
            dependencies: [:need_to_do_more_work?, :test_pid],
            default: "simple default"
          )
        end
      end

      def send_message(%{test_pid: test_pid} = deps) do
        send(test_pid, {:resolver_executed, Map.put(deps, :process_pid, self())})

        :ok
      end

      def should_execute?(%{need_to_do_more_work?: true}), do: true
      def should_execute?(_), do: false
    end

    test "when guard functions return false, no concurrent process is started to execute a batch field's resolver" do
      test_pid = self()

      workflow = %BatchWorkflowWithGuard{
        need_to_do_more_work?: false,
        other_field: "look for me in message mailbox",
        test_pid: test_pid
      }

      assert %BatchWorkflowWithGuard{guard_field: "simple default"} =
               Pacer.Workflow.execute(workflow)

      # The non-guarded field depends on `other_field`, pattern match on that to assert message is received from other process
      assert_receive {:resolver_executed,
                      %{other_field: "look for me in message mailbox", process_pid: process_pid}}

      refute process_pid == test_pid

      # The guarded field depends on need_to_do_more_work? and test_pid; refute this message was received because
      # the resolver should not run
      refute_receive {:resolver_executed, %{need_to_do_more_work?: false, test_pid: ^test_pid}}
    end

    test "when guard functions return true, a concurrent process is started to execute a batch field's resolver" do
      test_pid = self()

      workflow = %BatchWorkflowWithGuard{
        need_to_do_more_work?: true,
        other_field: "look for me in message mailbox",
        test_pid: test_pid
      }

      assert %BatchWorkflowWithGuard{guard_field: :ok} = Pacer.Workflow.execute(workflow)

      assert_receive {:resolver_executed,
                      %{other_field: "look for me in message mailbox", process_pid: process_pid}}

      refute process_pid == test_pid

      assert_receive {:resolver_executed,
                      %{need_to_do_more_work?: true, process_pid: guarded_process_pid}}

      refute guarded_process_pid == test_pid
    end
  end

  describe "visualization" do
    test "returns ok tuple with strict digraph as string" do
      assert {:ok, stringed_digraph} = TestGraph.__graph__(:visualization)

      assert stringed_digraph =~ "strict digraph"
      assert stringed_digraph =~ "label=\"http_requests\""
      assert stringed_digraph =~ "label=\"custom_field\""
      assert stringed_digraph =~ "label=\"field_with_default\""
      assert stringed_digraph =~ "label=\"field_a\""
    end

    test "when workflow is empty, return empty strict digraph as string" do
      defmodule EmptyGraph do
        use Pacer.Workflow

        graph do
        end
      end

      assert {:ok, "strict digraph {\n}\n"} = EmptyGraph.__graph__(:visualization)
    end
  end
end
