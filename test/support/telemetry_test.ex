defmodule TelemetryTest do
  @moduledoc """
  Remove this module once we upgrade to Telemetry 1.0+
  since there is a built in `telemetry_test` module
  we can use instead.
  """

  def handle_event(event, measurements, metadata, %{destination_pid: test_pid}) do
    send(test_pid, {event, measurements, metadata})
  end
end
