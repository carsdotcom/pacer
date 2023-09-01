defmodule PacerDocSample do
  @moduledoc """
  These are the existing moduledocs.
  """
  use Pacer.Workflow

  graph do
    field(:a, doc: "this is a field that contains data about a thing")

    field(:undocumented_field,
      resolver: &__MODULE__.fetch/1,
      dependencies: [:a, :service_call],
      default: "a default"
    )

    batch :api_requests do
      field(:service_call,
        default: nil,
        resolver: &__MODULE__.fetch/1,
        doc: "Fetches data from a service"
      )

      field(:undocumented_service_call, default: nil, resolver: &__MODULE__.fetch/1)
    end
  end

  def fetch(_), do: :ok
end
