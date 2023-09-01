defmodule Pacer.Workflow.Testing do
  @moduledoc """
  This module provides testing helpers for dependencies and fields for Pacer.Workflow.

  ## How to use in tests

  `use` this module in tests:

    use Pacer.Workflow.Testing

  This will allow you to use the helper assertions in your test module.

  Examples:
  ```elixir
  defmodule SomeWorkflowTest do
    use Pacer.Workflow.Testing

    defmodule TestGraph do
      use Pacer.Workflow

      graph do
        field(:field_a)

        field(:field_with_default,
          virtual?: true,
          default: "this is a default value"
        )

        batch :http_requests do
          field(:request_1,
            resolver: &__MODULE__.do_work/1,
            dependencies: [:field_a],
            default: 2
          )

          field(:request_2,
            resolver: &__MODULE__.do_work/1,
            dependencies: [:field_a],
            default: "this is a default value for request2"
          )
        end
      end

      def do_work(_), do: :ok
    end

    describe "testing graph dependencies and fields" do
      test "assert dependency of :field_a has no dependencies" do
        assert_dependencies(TestGraph, :field_a, [])
      end

      test "assert batch dependency of :request_2" do
        assert_batch_dependencies(TestGraph, :request_2, [:field_a])
      end

      test "provided fields match fields from workflow" do
        assert_fields(TestGraph, [
          :field_a,
          :field_with_default,
          :request_1,
          :request_2
        ])
      end
    end
  end
  ```
  """

  import ExUnit.Assertions, only: [assert: 2]

  defmacro __using__(_) do
    quote do
      alias Pacer.Workflow.Testing

      def assert_dependencies(workflow, field, dependencies) do
        Testing.assert_dependencies(workflow, field, dependencies)
      end

      def assert_batch_dependencies(workflow, batch_field, dependencies) do
        Testing.assert_batch_dependencies(workflow, batch_field, dependencies)
      end

      def assert_fields(workflow, fields) do
        Testing.assert_fields(workflow, fields)
      end
    end
  end

  @doc """
  Test helper to assert on non-batch field dependencies.
  First argument is your workflow, second is the field as an atom that you want to test,
  third are the dependencies you are passing in to be dependencies for the field passed in as the second argument.
  Note, the third argument should be a list of atoms or an empty list in the case of no dependencies.

  ## Example

  If we have a workflow defined as:
  ```elixir
  defmodule TestGraph do
    use Pacer.Workflow

    graph do
      field(:field_a)

      field(:field_b,
        resolver: &__MODULE__.do_work/1,
        dependencies: [:field_a]
      )
    end
  end
  ```

  We can test the dependencies of both fields:

  ```elixir
  test "assert :field_a has no dependencies" do
    assert_dependencies(TestGraph, :field_a, [])
  end

  test "assert dependencies of :field_b" do
    assert_dependencies(TestGraph, :field_b, [:field_a])
  end
  ```
  """
  @spec assert_dependencies(module(), atom(), list(atom())) :: true | no_return()
  def assert_dependencies(workflow, field, dependencies) do
    found_dependencies = find_dependencies(workflow, field)

    error_message = """
    Expected #{inspect(field)} to have dependencies: #{inspect(dependencies)}.

    Instead found: #{inspect(found_dependencies)}.
    """

    assert dependencies_for_field(dependencies, found_dependencies),
           error_message
  end

  @doc """
  Test helper to assert on batch field dependencies.
  First argument is your workflow, second is the batch field as an atom that you want to test,
  third are the dependencies you are passing in to be dependencies for the field passed in as the second argument.
  Note, the third argument should be a list of atoms or an empty list in the case of no dependencies.

  ## Example

  If we have a workflow defined as:
  ```elixir
  defmodule TestGraph do
    use Pacer.Workflow

    graph do
      field(:field_a)

      batch :http_requests do
        field(:request_1,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a],
          default: 2
        )

        field(:request_2,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a],
          default: "this is a default value for request2"
        )
      end
    end

    def do_work(_), do: :ok
  end
  ```

  We can test the dependencies of both fields:

  ```elixir
  test "assert batch fields have dependencies on :field_a" do
    assert_batch_dependencies(TestGraph, :request_1, [:field_a])
    assert_batch_dependencies(TestGraph, :request_2, [:field_a])
  end
  ```
  """
  @spec assert_batch_dependencies(module(), atom(), list(atom())) :: true | no_return()
  def assert_batch_dependencies(workflow, batch_field, dependencies) do
    found_dependencies = find_batch_dependencies(workflow, batch_field)

    error_message = """
    Expected batched field: #{inspect(batch_field)} to have dependencies: #{inspect(dependencies)}.

    Instead found: #{inspect(found_dependencies)}.
    """

    assert dependencies_for_field(dependencies, found_dependencies),
           error_message
  end

  @doc """
  Test helper to assert on the field defined in the workflow.
  First argument is your workflow, second is a list of atoms that are fields in the workflow.
  Ordering does not matter in the list of atoms since we use MapSets to do the comparison.

  ## Example

  If we have a workflow defined as:
  ```elixir
  defmodule TestGraph do
    use Pacer.Workflow

    graph do
      field(:field_a)

      field(:field_b,
        resolver: &__MODULE__.do_work/1,
        dependencies: [:field_a]
      )

      field(:field_with_default,
        virtual?: true,
        default: "this is a default value"
      )

      batch :http_requests do
        field(:request_1,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a],
          default: 2
        )

        field(:request_2,
          resolver: &__MODULE__.do_work/1,
          dependencies: [:field_a, :field_b],
          default: "this is a default value for request2"
        )
      end
    end

    def do_work(_), do: :ok
  end
  ```

  We can test the fields:
  ```elixir
  test "fields in the workflow" do
    assert_fields(TestGraph, [:field_a, :field_b, :request_2, :request_1])
  end
  ```
  """
  @spec assert_fields(module(), list(atom())) :: true | no_return()
  def assert_fields(workflow, fields) do
    workflow_fields = workflow.__graph__(:fields)

    error_message = """
    Expected #{inspect(workflow)} to have fields: #{inspect(fields)}.

    Instead found: #{inspect(workflow_fields)}.
    """

    assert MapSet.equal?(MapSet.new(fields), MapSet.new(workflow_fields)), error_message
  end

  @spec find_dependencies(module(), atom()) :: list(atom()) | nil
  defp find_dependencies(workflow, field) do
    dependencies = workflow.__graph__(:dependencies)

    dependencies
    |> Enum.find(fn {found_field, _dependencies} ->
      found_field == field
    end)
    |> case do
      {_field, found_dependencies} -> found_dependencies
      nil -> nil
    end
  end

  @spec find_batch_dependencies(module(), atom()) :: list(atom()) | nil
  defp find_batch_dependencies(workflow, field) do
    dependencies = workflow.__graph__(:batch_dependencies)

    dependencies
    |> Enum.find(fn {_batch_name, found_field, _dependencies} ->
      found_field == field
    end)
    |> case do
      {_batch_name, _field, found_dependencies} -> found_dependencies
      nil -> nil
    end
  end

  @spec dependencies_for_field(list(atom()), list(atom()) | nil) :: boolean()
  defp dependencies_for_field(_dependencies, nil), do: false

  defp dependencies_for_field(dependencies, found_dependencies) do
    MapSet.equal?(MapSet.new(dependencies), MapSet.new(found_dependencies))
  end
end
