defmodule Pacer.Workflow.TestingTest do
  use ExUnit.Case
  use Pacer.Workflow.Testing

  defmodule TestGraph do
    use Pacer.Workflow

    graph do
      field(:field_a_dependency)

      field(:field_a,
        resolver: &__MODULE__.do_work/1,
        dependencies: [:field_a_dependency]
      )

      field(:field_with_default,
        virtual?: true,
        default: "this is a default value"
      )

      batch :http_requests do
        field(:request_1,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a_dependency],
          default: 2
        )

        field(:request_2,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a_dependency, :field_a],
          default: "this is a default value for request2"
        )
      end
    end

    def do_work(_), do: :ok
  end

  defmodule EmptyGraph do
    use Pacer.Workflow

    graph do
    end
  end

  describe "assert_dependencies/3" do
    test "when provided dependencies for field matches graph definition dependencies for field" do
      assert_dependencies(TestGraph, :field_a, [
        :field_a_dependency
      ])
    end

    test "provided field has dependencies but do not match input dependencies" do
      assert_dependencies(TestGraph, :field_a, [])
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message ==
                 """
                 Expected :field_a to have dependencies: [].

                 Instead found: [:field_a_dependency].
                 """
    end

    test "field does not have dependencies" do
      assert_dependencies(TestGraph, :field_with_default, [
        :definitely_a_dependency
      ])
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message ==
                 """
                 Expected :field_with_default to have dependencies: [:definitely_a_dependency].

                 Instead found: [].
                 """
    end
  end

  describe "assert_batch_dependencies/3" do
    test "when provided dependencies for field matches graph definition dependencies for field" do
      assert_batch_dependencies(TestGraph, :request_2, [
        :field_a_dependency,
        :field_a
      ])
    end

    test "provided field has dependencies but do not match input dependencies" do
      assert_batch_dependencies(TestGraph, :request_2, [])
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message ==
                 """
                 Expected batched field: :request_2 to have dependencies: [].

                 Instead found: [:field_a_dependency, :field_a].
                 """
    end
  end

  describe "assert_fields/2" do
    test "provided fields match fields from workflow" do
      assert_fields(TestGraph, [
        :field_a_dependency,
        :field_a,
        :field_with_default,
        :request_1,
        :request_2
      ])
    end

    test "provided fields do not match graph fields" do
      assert_fields(EmptyGraph, [:field_1])
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message ==
                 """
                 Expected Pacer.Workflow.TestingTest.EmptyGraph to have fields: [:field_1].

                 Instead found: [].
                 """
    end
  end
end
