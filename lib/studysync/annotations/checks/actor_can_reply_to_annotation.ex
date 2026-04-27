defmodule Studysync.Annotations.Checks.ActorCanReplyToAnnotation do
  @moduledoc """
  Authorizes the actor only if they can read the parent annotation under the
  same rules as `Studysync.Annotations.Annotation`'s read policy:

    * `:workspace`-visible annotation → any active workspace member of the
      annotation's resource
    * `:private` annotation → only the author

  This keeps the reply policy in lock-step with annotation visibility so a
  reply path can never widen access beyond what the annotation itself allows.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_), do: "actor can read the parent annotation"

  @impl true
  def match?(nil, _, _), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    annotation_id =
      Ash.Changeset.get_argument(changeset, :annotation_id) ||
        Ash.Changeset.get_attribute(changeset, :annotation_id)

    can_reply?(actor, annotation_id)
  end

  def match?(_actor, _context, _opts), do: false

  defp can_reply?(_actor, nil), do: false

  defp can_reply?(actor, annotation_id) do
    case Studysync.Annotations.Annotation
         |> Ash.Query.filter(id == ^annotation_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %{visibility: :private, user_id: user_id}} ->
        user_id == actor.id

      {:ok, %{visibility: :workspace, resource_id: resource_id}}
      when not is_nil(resource_id) ->
        workspace_member?(actor, resource_id)

      _ ->
        false
    end
  end

  defp workspace_member?(actor, resource_id) do
    with {:ok, %{workspace_id: workspace_id}} when not is_nil(workspace_id) <-
           Studysync.Library.Resource
           |> Ash.Query.filter(id == ^resource_id)
           |> Ash.read_one(authorize?: false),
         {:ok, %{}} <-
           Studysync.Workspaces.Membership
           |> Ash.Query.filter(
             workspace_id == ^workspace_id and
               user_id == ^actor.id and
               status == :active
           )
           |> Ash.read_one(authorize?: false) do
      true
    else
      _ -> false
    end
  end
end
