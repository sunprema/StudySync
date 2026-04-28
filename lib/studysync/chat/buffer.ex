defmodule Studysync.Chat.Buffer do
  @moduledoc """
  Per-resource ring buffer for transient chat (Slice 18).

  A single GenServer fronts an ETS table keyed by `resource_id`. All writes go
  through the GenServer so the read-modify-write that trims the list to the
  last `@max_messages` items is race-free. Reads hit ETS directly via
  `recent/2` so the chat panel mount stays off the GenServer hot path.

  Buffers live for the lifetime of the BEAM node — restart the app and chat
  history is gone. That's the design (CLAUDE.md §4 doesn't apply: chat is not
  a domain resource and has no Ash backing).

  Rate-limit state (sender_id → list of recent send timestamps) lives in the
  same GenServer for the same reason: writes need to be serialized to be
  meaningful.
  """

  use GenServer

  alias Studysync.Chat.Message

  @table __MODULE__
  @max_messages 50
  @rate_limit_count 5
  @rate_limit_window_ms 3_000

  # ---------- public API ----------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Append a message to the resource's buffer and return the stored struct.

  Returns `{:error, :rate_limited}` if the same user has sent
  `#{@rate_limit_count}` messages within the last
  `#{@rate_limit_window_ms}`ms.
  """
  @spec append(binary(), binary(), String.t(), String.t()) ::
          {:ok, Message.t()} | {:error, :rate_limited}
  def append(resource_id, user_id, user_email, body)
      when is_binary(resource_id) and is_binary(user_id) and is_binary(user_email) and
             is_binary(body) do
    GenServer.call(__MODULE__, {:append, resource_id, user_id, user_email, body})
  end

  @doc """
  Return up to `n` most recent messages for `resource_id`, oldest first.
  Hits ETS directly — no GenServer hop.
  """
  @spec recent(binary(), pos_integer()) :: [Message.t()]
  def recent(resource_id, n \\ @max_messages) when is_binary(resource_id) and n > 0 do
    case :ets.lookup(@table, resource_id) do
      [{^resource_id, messages}] -> messages |> Enum.take(-n)
      [] -> []
    end
  end

  @doc "Test-only: drop everything. Don't call from product code."
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # ---------- GenServer ----------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, %{rate: %{}}}
  end

  @impl true
  def handle_call({:append, resource_id, user_id, user_email, body}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case check_rate(state.rate, user_id, now) do
      {:ok, rate} ->
        message = build_message(resource_id, user_id, user_email, body)
        existing = lookup(resource_id)
        updated = trim(existing ++ [message])
        :ets.insert(@table, {resource_id, updated})
        {:reply, {:ok, message}, %{state | rate: rate}}

      :rate_limited ->
        {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, %{rate: %{}}}
  end

  # ---------- helpers ----------

  defp lookup(resource_id) do
    case :ets.lookup(@table, resource_id) do
      [{^resource_id, messages}] -> messages
      [] -> []
    end
  end

  defp trim(messages) when length(messages) > @max_messages do
    Enum.take(messages, -@max_messages)
  end

  defp trim(messages), do: messages

  defp build_message(resource_id, user_id, user_email, body) do
    %Message{
      id: Ecto.UUID.generate(),
      resource_id: resource_id,
      user_id: user_id,
      user_email: user_email,
      body: body,
      sent_at: DateTime.utc_now()
    }
  end

  defp check_rate(rate, user_id, now) do
    cutoff = now - @rate_limit_window_ms
    recent = rate |> Map.get(user_id, []) |> Enum.filter(&(&1 >= cutoff))

    if length(recent) >= @rate_limit_count do
      :rate_limited
    else
      {:ok, Map.put(rate, user_id, [now | recent])}
    end
  end

  @doc false
  def max_messages, do: @max_messages

  @doc false
  def rate_limit_count, do: @rate_limit_count

  @doc false
  def rate_limit_window_ms, do: @rate_limit_window_ms
end
