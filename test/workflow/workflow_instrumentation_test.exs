defmodule Pacer.WorkflowInstrumentationTest do
  use ExUnit.Case

  alias Pacer.Workflow

  defmodule InstrumentationTestGraph do
    use Pacer.Workflow

    graph do
      field(:custom_field)
      field(:field_a, resolver: &__MODULE__.do_work/1, dependencies: [:custom_field])
      field(:field_with_default, default: "this is a default value")

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

  defmodule TelemetryHandlers do
    def handle_event(event, measurements, metadata, config) do
      receiver_pid =
        case config do
          %{receiver_pid: receiver_pid} -> receiver_pid
          _ -> self()
        end

      send(receiver_pid, {:event_handled, event, measurements, metadata, config})
    end
  end

  describe "Pacer Workflow Telemetry" do
    setup context do
      on_exit(fn -> :telemetry.detach(context[:test]) end)
      :ok
    end

    test "emits [:pacer, :vertex_execute, :start/:stop] events for field resolvers executed sequentially",
         context do
      :telemetry.attach_many(
        context[:test],
        [[:pacer, :execute_vertex, :start], [:pacer, :execute_vertex, :stop]],
        &TelemetryHandlers.handle_event/4,
        nil
      )

      assert %InstrumentationTestGraph{field_a: :ok} =
               Workflow.execute(%InstrumentationTestGraph{})

      assert_receive {:event_handled, [:pacer, :execute_vertex, :start], _measurements,
                      start_metadata, _config}

      assert_receive {:event_handled, [:pacer, :execute_vertex, :stop], _measurements,
                      stop_metadata, _config}

      assert start_metadata[:field] == :field_a
      assert stop_metadata[:field] == :field_a
      assert start_metadata[:workflow] == InstrumentationTestGraph
      assert stop_metadata[:workflow] == InstrumentationTestGraph
    end

    test "emits [:pacer, :vertex_execute, :start/:stop] events for field resolvers executed concurrently",
         context do
      test_pid = self()
      config = %{receiver_pid: test_pid}

      :telemetry.attach_many(
        context[:test],
        [[:pacer, :execute_vertex, :start], [:pacer, :execute_vertex, :stop]],
        &TelemetryHandlers.handle_event/4,
        config
      )

      assert %InstrumentationTestGraph{request_1: _, request_2: _} =
               Workflow.execute(%InstrumentationTestGraph{})

      assert_receive {:event_handled, [:pacer, :execute_vertex, :start], _measurements,
                      %{field: :request_1, parent_pid: ^test_pid}, _}

      assert_receive {:event_handled, [:pacer, :execute_vertex, :stop], _measurements,
                      %{parent_pid: ^test_pid}, _}

      assert_receive {:event_handled, [:pacer, :execute_vertex, :start], _measurements,
                      %{field: :request_2, parent_pid: ^test_pid}, _}

      assert_receive {:event_handled, [:pacer, :execute_vertex, :stop], _measurements,
                      %{parent_pid: ^test_pid}, _}
    end

    defmodule InstrumentedGraphWithError do
      use Pacer.Workflow

      graph do
        field(:initial_field, default: "a")
        field(:a, resolver: &__MODULE__.resolver/1, dependencies: [:initial_field])
      end

      def resolver(_) do
        raise "oops"
      end
    end

    test "emits [:pacer, :execute_vertex, :exception] events when an exception is raised on a sequential field resolver",
         context do
      :telemetry.attach(
        context[:test],
        [:pacer, :execute_vertex, :exception],
        &TelemetryHandlers.handle_event/4,
        nil
      )

      assert_raise RuntimeError, fn ->
        Workflow.execute(InstrumentedGraphWithError)
      end

      assert_receive {:event_handled, [:pacer, :execute_vertex, :exception], _measurements,
                      metadata, _config}

      assert %{
               field: _,
               kind: :error,
               reason: %RuntimeError{},
               stacktrace: stacktrace,
               workflow: InstrumentedGraphWithError
             } = metadata

      assert is_list(stacktrace)
    end
  end

  defmodule GraphWithBatchErrors do
    use Pacer.Workflow

    graph do
      field(:a, default: "this is a default value")

      batch :requests do
        field(:one,
          resolver: &__MODULE__.bad_resolver/1,
          default: "this is a fallback",
          dependencies: [:a]
        )

        field(:two,
          resolver: &__MODULE__.bad_resolver/1,
          default: "another fallback",
          dependencies: [:a]
        )
      end
    end

    def bad_resolver(_) do
      raise "oh no, this is not good"
    end
  end

  test "emits a [:pacer, :execute_vertex, :exception] event when an exception is raised from a batched field resolver",
       context do
    test_pid = self()
    config = %{receiver_pid: test_pid}

    :telemetry.attach(
      context[:test],
      [:pacer, :execute_vertex, :exception],
      &TelemetryHandlers.handle_event/4,
      config
    )

    _ = Workflow.execute(%GraphWithBatchErrors{})

    assert_receive {:event_handled, [:pacer, :execute_vertex, :exception], _measurements,
                    metadata, _config}

    assert %{
             field: :one,
             kind: :error,
             parent_pid: ^test_pid,
             reason: %RuntimeError{},
             stacktrace: _,
             workflow: GraphWithBatchErrors
           } = metadata
  end
end
