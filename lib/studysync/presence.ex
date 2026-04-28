defmodule Studysync.Presence do
  @moduledoc """
  Phoenix.Presence registry shared across the app.

  Added in Slice 18 for the chat drawer's "here now" count, but registered
  as a generic presence module — anything that wants to track who's
  currently looking at a resource (or workspace, or study room) can ride
  the same registry by tracking on its own topic.

  Topics in use:

    * `"resource:" <> resource_id <> ":chat"` — readers connected to a
      resource's chat drawer (Slice 18). Track key is the user_id; metadata
      carries `email` so the panel can render avatars without a DB hop.
  """

  use Phoenix.Presence,
    otp_app: :studysync,
    pubsub_server: Studysync.PubSub
end
