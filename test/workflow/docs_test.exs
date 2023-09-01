defmodule Pacer.DocsTest do
  use ExUnit.Case

  alias Pacer.Docs

  describe "generate/0 macro" do
    test "generates a string of markdown describing the fields" do
      {_, _, _, _, %{"en" => moduledocs}, _, _} = Code.fetch_docs(PacerDocSample)

      assert moduledocs ==
               "These are the existing moduledocs.\n\n## Pacer Fields:\n\n\n - `undocumented_service_call`\n\t - **Batch**: `api_requests`\n\t - **Default**: `nil`\n\t - *No dependencies*\n\n - `service_call`\n\t - Fetches data from a service\n\t - **Batch**: `api_requests`\n\t - **Default**: `nil`\n\t - *No dependencies*\n\n - `undocumented_field`\n\t - **Default**: `\"a default\"`\n\t - **Depends on**: `[:a, :service_call]`\n\n - `a`\n\t - this is a field that contains data about a thing\n\t - *No dependencies*\n"
    end
  end

  describe "write_docs/1" do
    test "returns an empty string when given an empty string" do
      assert "" == Docs.write_doc("")
    end

    test "returns the docs passed with a tab and bullet prefix" do
      doc = "this is some documentation for a field"

      assert "\t - #{doc}\n" == Docs.write_doc(doc)
    end
  end

  describe "write_default/1" do
    test "returns an empty string if a field's default is not given" do
      assert "" == Docs.write_default(%Pacer.Workflow.FieldNotSet{})
    end

    test "returns the default value with some additional markdown prefixing" do
      default = [this: "is just a default"]

      assert "\t - **Default**: `#{inspect(default)}`\n" == Docs.write_default(default)
    end
  end

  describe "write_dependencies/1" do
    test "returns markdown indicating there are no dependencies when given an empty list" do
      assert "\t - *No dependencies*\n" == Docs.write_dependencies([])
    end

    test "returns the list of field dependencies in markdown" do
      deps = [:some_dep_one, :some_dep_two]

      assert "\t - **Depends on**: `#{inspect(deps)}`\n" == Docs.write_dependencies(deps)
    end
  end
end
