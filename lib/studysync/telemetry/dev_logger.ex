defmodule Studysync.Telemetry.DevLogger do
  @moduledoc """
  Slice 15.3 — dev-only telemetry handler that surfaces slow LiveView and
  Studysync events to the iex/server console.

  Phoenix.LiveView already emits `[:phoenix, :live_view, *, :stop]` events;
  the StudySync hot paths (annotation create, PubSub broadcast) emit
  `[:studysync, *, :stop]` events from Slice 15.5. We attach a logger that
  fires only when an event exceeds its threshold so steady-state operation
  stays quiet.

  Attached from `Studysync.Application.start/2` only when the application is
  configured for `:dev` (see config/dev.exs). Production never installs the
  handler.
  """

  require Logger

  @handler_id "studysync-dev-telemetry-logger"

  # Thresholds in *milliseconds*. Picked to surface anything that would
  # threaten the <100ms perceived-latency budget in CLAUDE.md §6 without
  # spamming the console for routine ticks.
  @lv_handle_event_threshold_ms 50
  @lv_mount_threshold_ms 200
  @annotation_create_threshold_ms 75
  @pubsub_broadcast_threshold_ms 25

  @doc """
  Attach the dev logger. Idempotent — re-attaching is a no-op.
  """
  def attach do
    :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      [
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :mount, :stop],
        [:studysync, :annotations, :create, :stop],
        [:studysync, :pubsub, :broadcast, :stop]
      ],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    duration_ms = native_to_ms(measurements[:duration])

    if duration_ms >= threshold_for(event) do
      Logger.debug(fn ->
        "telemetry slow=#{Float.round(duration_ms, 1)}ms event=#{Enum.join(event, ".")} #{inspect_meta(metadata)}"
      end)
    end
  end

  defp threshold_for([:phoenix, :live_view, :handle_event, :stop]),
    do: @lv_handle_event_threshold_ms

  defp threshold_for([:phoenix, :live_view, :mount, :stop]), do: @lv_mount_threshold_ms

  defp threshold_for([:studysync, :annotations, :create, :stop]),
    do: @annotation_create_threshold_ms

  defp threshold_for([:studysync, :pubsub, :broadcast, :stop]),
    do: @pubsub_broadcast_threshold_ms

  defp threshold_for(_), do: 0

  defp native_to_ms(nil), do: 0.0
  defp native_to_ms(native), do: System.convert_time_unit(native, :native, :microsecond) / 1_000

  # Trim metadata to the keys we actually care about for diagnostics; raw
  # metadata can include socket structs which would explode the log line.
  defp inspect_meta(meta) do
    meta
    |> Map.take([:event, :type, :topic, :outcome, :view, :resource_id])
    |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{inspect(v)}" end)
  end
end
