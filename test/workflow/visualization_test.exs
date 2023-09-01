defmodule Pacer.Workflow.VisualizationTest do
  use ExUnit.Case, async: true

  alias Pacer.Workflow.Visualization

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

  defmodule EmptyGraph do
    use Pacer.Workflow

    graph do
    end
  end

  describe "visualize/2" do
    test "with not options provided, sets default path and filename" do
      date = Calendar.strftime(NaiveDateTime.utc_now(), "%Y-%m-%d")

      filename_path =
        File.cwd!() <>
          "/" <> "Pacer.Workflow.VisualizationTest.TestGraph_strict_digraph_string_" <> "#{date}"

      assert :ok == Visualization.visualize(TestGraph)
      assert File.exists?(filename_path)

      File.rm!(filename_path)
    end

    test "when workflow is empty, still creates file" do
      date = Calendar.strftime(NaiveDateTime.utc_now(), "%Y-%m-%d")

      filename_path =
        File.cwd!() <>
          "/" <> "Pacer.Workflow.VisualizationTest.EmptyGraph_strict_digraph_string_" <> "#{date}"

      assert :ok == Visualization.visualize(EmptyGraph)
      assert File.exists?(filename_path)

      File.rm!(filename_path)
    end

    test "when options are provided, set path and filename to passed in options" do
      File.mkdir_p("tmp/")
      path = "tmp/"
      filename = "filename_here"

      filename_path = path <> filename
      assert :ok == Visualization.visualize(TestGraph, path: path, filename: filename)
      assert File.exists?(filename_path)

      File.rm_rf!("tmp")
    end
  end
end
