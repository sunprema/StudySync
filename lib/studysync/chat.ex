defmodule Studysync.Chat do
  @moduledoc """
  Transient, per-resource chat (Slice 18).

  ## Why this isn't an Ash resource

  Every other domain entity in StudySync is an Ash resource (CLAUDE.md §4.1).
  Chat is the carve-out: messages are *intentionally* not persisted to the
  DB. They live in `Studysync.Chat.Buffer`'s ETS-backed ring buffer for the
  lifetime of the BEAM node, then they're gone. There's nothing for Ash to
  back, no migrations, no policies — just an in-memory side-channel that
  rides Phoenix.PubSub.

  Authorization is enforced here in plain Elixir: only active workspace
  members of the resource's workspace can `send_message/3`. Reads are
  implicitly scoped to whoever can already open the reader (so the existing
  `Library.Resource` policy gates `recent/2` indirectly).

  ## Public surface

  - `send_message/3` — append-and-broadcast, with rate-limit + length checks.
  - `recent/2` — last N messages for a resource, oldest first.
  - `subscribe/1` / `unsubscribe/1` — Phoenix.PubSub topic helpers.
  """

  alias Studysync.Chat.{Buffer, Message, PubSub}
  alias Studysync.Library
  alias Studysync.Workspaces

  @max_body_length 500

  @type send_error ::
          :unauthorized
          | :empty_body
          | :body_too_long
          | :rate_limited
          | :resource_not_found

  @doc """
  Send a chat message from `actor` into `resource_id`'s chat topic.

  Returns `{:ok, %Message{}}` on success. Possible errors:

  - `:unauthorized` — actor is not an active member of the workspace.
  - `:empty_body` — body trims to an empty string.
  - `:body_too_long` — body exceeds #{@max_body_length} characters.
  - `:rate_limited` — actor exceeded the per-user send window.
  - `:resource_not_found` — resource does not exist or actor can't see it.
  """
  @spec send_message(map(), binary(), String.t()) ::
          {:ok, Message.t()} | {:error, send_error()}
  def send_message(actor, resource_id, body)
      when is_map(actor) and is_binary(resource_id) and is_binary(body) do
    with {:ok, trimmed} <- validate_body(body),
         {:ok, workspace_id} <- fetch_workspace_id(actor, resource_id),
         :ok <- authorize(actor, workspace_id),
         {:ok, message} <-
           Buffer.append(resource_id, actor.id, to_string(actor.email), trimmed) do
      PubSub.broadcast_message_sent(message)
      {:ok, message}
    end
  end

  @doc "Most recent `n` messages for `resource_id`, oldest first."
  @spec recent(binary(), pos_integer()) :: [Message.t()]
  def recent(resource_id, n \\ 50), do: Buffer.recent(resource_id, n)

  @doc "Subscribe the calling process to chat events for `resource_id`."
  defdelegate subscribe(resource_id), to: PubSub
  defdelegate unsubscribe(resource_id), to: PubSub

  @doc false
  def max_body_length, do: @max_body_length

  # ---------- helpers ----------

  defp validate_body(body) do
    trimmed = String.trim(body)

    cond do
      trimmed == "" -> {:error, :empty_body}
      String.length(trimmed) > @max_body_length -> {:error, :body_too_long}
      true -> {:ok, trimmed}
    end
  end

  # Read with `authorize?: false` so we can distinguish "no such resource"
  # from "you aren't a member" — only `workspace_id` (a routing field) is
  # used; no annotation/text content is exposed. The membership check below
  # is the real gate.
  defp fetch_workspace_id(_actor, resource_id) do
    case Ash.get(Library.Resource, resource_id, authorize?: false) do
      {:ok, %{workspace_id: workspace_id}} -> {:ok, workspace_id}
      _ -> {:error, :resource_not_found}
    end
  end

  defp authorize(actor, workspace_id) do
    if Workspaces.actor_member?(workspace_id, actor) do
      :ok
    else
      {:error, :unauthorized}
    end
  end
end
