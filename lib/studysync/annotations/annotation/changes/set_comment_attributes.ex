defmodule Studysync.Annotations.Annotation.Changes.SetCommentAttributes do
  @moduledoc """
  Lifts the `:create_comment` action's arguments onto the changeset's
  attributes. Visibility defaults to `:workspace` if the caller didn't pick.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    visibility = Ash.Changeset.get_argument(changeset, :visibility) || :workspace

    changeset
    |> Ash.Changeset.change_attribute(
      :resource_id,
      Ash.Changeset.get_argument(changeset, :resource_id)
    )
    |> Ash.Changeset.change_attribute(
      :page_number,
      Ash.Changeset.get_argument(changeset, :page_number)
    )
    |> Ash.Changeset.change_attribute(:rect, Ash.Changeset.get_argument(changeset, :rect))
    |> Ash.Changeset.change_attribute(:text, Ash.Changeset.get_argument(changeset, :text))
    |> Ash.Changeset.change_attribute(:body, Ash.Changeset.get_argument(changeset, :body))
    |> Ash.Changeset.change_attribute(:visibility, visibility)
  end
end
