defmodule Studysync.Chat.Message do
  @moduledoc """
  Plain struct for a chat message. Not an Ash resource — chat is intentionally
  transient (Slice 18) and never persists to the DB. Lives in the per-resource
  ring buffer (`Studysync.Chat.Buffer`) for the lifetime of the BEAM node.
  """

  @enforce_keys [:id, :resource_id, :user_id, :user_email, :body, :sent_at]
  defstruct [:id, :resource_id, :user_id, :user_email, :body, :sent_at]

  @type t :: %__MODULE__{
          id: binary(),
          resource_id: binary(),
          user_id: binary(),
          user_email: String.t(),
          body: String.t(),
          sent_at: DateTime.t()
        }
end
