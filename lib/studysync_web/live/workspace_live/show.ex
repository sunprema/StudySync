defmodule StudysyncWeb.WorkspaceLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Workspaces
  alias Studysync.Workspaces.Membership

  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Workspaces.get_workspace(id, actor: actor, load: [memberships: [:user]]) do
      {:ok, workspace} when not is_nil(workspace) ->
        admin? = admin?(workspace, actor)

        {:ok,
         socket
         |> assign(workspace: workspace, admin?: admin?, page_title: workspace.name)
         |> assign(:invite_form, if(admin?, do: build_invite_form(workspace, actor)))}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Workspace not found.")
         |> push_navigate(to: ~p"/workspaces")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-8 py-12">
      <header class="border-b border-paper-2 pb-6 mb-10 flex items-baseline justify-between gap-6">
        <div>
          <p class="font-mono text-xs uppercase tracking-widest text-ink-soft">Workspace</p>
          <h1 class="font-display text-5xl text-ink mt-1">{@workspace.name}</h1>
        </div>
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/workspaces/#{@workspace.id}/library"}
            class="font-mono text-xs uppercase tracking-widest text-ink-soft hover:text-terracotta"
          >
            Library →
          </.link>
          <StudysyncWeb.Layouts.user_menu current_user={@current_user} />
        </div>
      </header>

      <section class="mb-12">
        <h2 class="font-mono text-xs uppercase tracking-widest text-ink-soft mb-4">
          Members · <span class="num">{length(@workspace.memberships)}</span>
        </h2>

        <ul class="divide-y divide-paper-2">
          <li
            :for={member <- @workspace.memberships}
            id={"membership-#{member.id}"}
            class="py-3 flex items-baseline justify-between"
          >
            <span class="font-serif text-ink">{member_label(member)}</span>
            <span class="font-mono text-xs uppercase tracking-widest text-ink-soft">
              {member.role} · {member.status}
            </span>
          </li>
        </ul>
      </section>

      <section :if={@admin?} class="border-t border-paper-2 pt-8">
        <h2 class="font-mono text-xs uppercase tracking-widest text-ink-soft mb-4">
          Invite a member
        </h2>

        <.form
          for={@invite_form}
          id="invite-form"
          phx-change="validate_invite"
          phx-submit="submit_invite"
          class="flex gap-3 items-end"
        >
          <input type="hidden" name="form[workspace_id]" value={@workspace.id} />
          <div class="flex-1">
            <.input
              field={@invite_form[:email]}
              type="email"
              label="Email"
              placeholder="reader@example.com"
              required
            />
          </div>
          <button type="submit" class="btn btn-primary mb-2">Send invite</button>
        </.form>
      </section>
    </div>
    """
  end

  def handle_event("validate_invite", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.invite_form, params)
    {:noreply, assign(socket, :invite_form, form)}
  end

  def handle_event("submit_invite", %{"form" => %{"email" => email}}, socket) do
    actor = socket.assigns.current_user
    workspace_id = socket.assigns.workspace.id

    case Workspaces.invite_member(workspace_id, email, actor: actor) do
      {:ok, membership} ->
        workspace = reload_workspace!(workspace_id, actor)
        flash = invite_flash(membership)

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> assign(:workspace, workspace)
         |> assign(:invite_form, build_invite_form(workspace, actor))}

      {:error, :already_member} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "#{email} is already a member of this workspace."
         )}

      {:error, _other} ->
        {:noreply, put_flash(socket, :error, "Could not send invitation.")}
    end
  end

  defp invite_flash(%{updated_at: updated_at, inserted_at: inserted_at})
       when updated_at != inserted_at,
       do: "Invitation re-sent."

  defp invite_flash(_), do: "Invitation sent."

  defp member_label(%{user: %{email: email}}) when not is_nil(email), do: to_string(email)

  defp member_label(%{invite_email: email}) when not is_nil(email),
    do: "#{email} (invited)"

  defp member_label(_), do: "Unknown"

  defp admin?(workspace, actor) do
    Enum.any?(workspace.memberships, fn m ->
      m.user_id == actor.id and m.role == :admin and m.status == :active
    end)
  end

  defp reload_workspace!(id, actor) do
    Workspaces.get_workspace!(id, actor: actor, load: [memberships: [:user]])
  end

  defp build_invite_form(workspace, actor) do
    Membership
    |> AshPhoenix.Form.for_create(:invite,
      actor: actor,
      params: %{"workspace_id" => workspace.id}
    )
    |> to_form()
  end
end
