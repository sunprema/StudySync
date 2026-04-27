defmodule StudysyncWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("studysync.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("studysync.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("studysync.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("studysync.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("studysync.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # StudySync — Slice 15.5 instrumentation
      summary("studysync.annotations.create.stop.duration",
        unit: {:native, :millisecond},
        tags: [:type, :outcome],
        description: "End-to-end Ash create latency for an annotation"
      ),
      summary("studysync.pubsub.broadcast.stop.duration",
        unit: {:native, :millisecond},
        tags: [:event],
        description: "Phoenix.PubSub broadcast fan-out latency"
      ),
      # Slice 11 stub — fires once the AI worker lands.
      summary("studysync.ai.answer.stop.duration",
        unit: {:native, :millisecond},
        tags: [:outcome],
        description: "Anthropic call duration inside the Ask AI Oban worker"
      ),

      # Phoenix LiveView — Slice 15.3 audit signal. These are emitted by
      # Phoenix.LiveView itself; we just opt into the metrics so the
      # ConsoleReporter (or any future reporter) can surface them.
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view]
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view, :event]
      ),
      summary("phoenix.live_view.handle_params.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view]
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {StudysyncWeb, :count_users, []}
    ]
  end
end
