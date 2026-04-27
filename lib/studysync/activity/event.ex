defmodule Studysync.Activity.Event do
  @moduledoc """
  A single item in a workspace's activity feed.

  Not an Ash resource — events are derived on read from existing resources
  (annotations and their replies). The struct is the shape the LiveView
  renders, not a row in a table. Future event sources (`:completed_chapter`
  in Slice 9, `:stamped` in Slice 13) plug into the same shape.

  `id` is namespaced with the source so the rail's stream can hold an
  annotation event and a reply event with no risk of DOM-id collision.
  """

  @type type :: :highlighted | :commented | :completed_chapter | :stamped

  @type t :: %__MODULE__{
          id: String.t(),
          type: type(),
          actor_email: String.t() | nil,
          resource_id: Ash.UUID.t() | nil,
          resource_title: String.t() | nil,
          annotation_id: Ash.UUID.t() | nil,
          page_number: integer() | nil,
          snippet: String.t() | nil,
          inserted_at: DateTime.t()
        }

  defstruct [
    :id,
    :type,
    :actor_email,
    :resource_id,
    :resource_title,
    :annotation_id,
    :page_number,
    :snippet,
    :inserted_at
  ]
end
