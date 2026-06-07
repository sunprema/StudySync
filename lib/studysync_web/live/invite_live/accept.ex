defmodule StudysyncWeb.InviteLive.Accept do
  @moduledoc """
  Accept-invite landing page. Verifies a signed token, looks up the pending
  membership, and on confirm calls `Workspaces.accept_invite` as the current
  user. Renders distinct states for: invalid/expired token, missing
  membership, already accepted, wrong user, signed-out, and ready-to-accept.
  """

  use StudysyncWeb, :live_view

  require Ash.Query

  alias Studysync.Workspaces
  alias Studysync.Workspaces.Membership
  alias Studysync.Workspaces.Membership.Senders.SendInviteEmail

  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, :token, token)

    case SendInviteEmail.verify_token(token) do
      {:ok, membership_id} -> load_state(socket, membership_id)
      {:error, _reason} -> {:ok, assign(socket, :state, :invalid_token)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-paper flex flex-col items-center justify-center px-6 py-16">
      <div class="w-full max-w-md">
        <p class="section-label mb-6">Invitation</p>

        <div class="card">
          <%= case @state do %>
            <% :invalid_token -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">Invitation expired</h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  This invite link is invalid or older than 14 days. Ask the workspace admin to resend.
                </p>
              </div>
            <% :missing -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">Invitation not found</h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  This invitation no longer exists.
                </p>
              </div>
            <% :already_active -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">Already a member</h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  You're already in <strong class="font-semibold text-ink">{@workspace.name}</strong>.
                </p>
                <.link navigate={~p"/workspaces/#{@workspace.id}"} class="btn btn-primary">
                  Go to workspace
                </.link>
              </div>
            <% :signed_out -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">
                  You're invited to {@workspace.name}
                </h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  Sign in or create an account with
                  <strong class="font-semibold text-ink not-italic">
                    {to_string(@invite_email)}
                  </strong>
                  to accept.
                </p>
                <div class="flex gap-3 pt-2">
                  <.link navigate={~p"/sign-in"} class="btn btn-primary">Sign in</.link>
                  <.link navigate={~p"/register"} class="btn btn-ghost">Create account</.link>
                </div>
              </div>
            <% :wrong_user -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">Not your invitation</h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  This invitation was sent to a different email. Sign in as that user to accept.
                </p>
              </div>
            <% :ready -> %>
              <div class="card-pad space-y-4">
                <h1 class="font-display text-3xl text-ink">
                  Join {@workspace.name}
                </h1>
                <p class="font-serif italic text-ink-soft text-sm leading-relaxed">
                  You've been invited to join this workspace. Accept to get access to the library and start reading with the group.
                </p>
                <div class="pt-2">
                  <button type="button" phx-click="accept" class="btn btn-primary">
                    Accept invitation
                  </button>
                </div>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("accept", _params, socket) do
    %{membership: membership} = socket.assigns
    actor = socket.assigns.current_user

    case Workspaces.accept_invite(membership, actor: actor) do
      {:ok, accepted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Welcome to #{socket.assigns.workspace.name}.")
         |> push_navigate(to: ~p"/workspaces/#{accepted.workspace_id}")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not accept invitation.")}
    end
  end

  defp load_state(socket, membership_id) do
    case fetch_membership(membership_id) do
      nil ->
        {:ok, assign(socket, :state, :missing)}

      membership ->
        socket
        |> assign(:membership, membership)
        |> assign(:workspace, membership.workspace)
        |> classify(membership)
    end
  end

  defp classify(socket, %{status: :active} = _membership) do
    {:ok, assign(socket, :state, :already_active)}
  end

  defp classify(socket, membership) do
    current_user = socket.assigns[:current_user]
    invite_email = invite_email(membership)

    cond do
      is_nil(current_user) ->
        {:ok, assign(socket, state: :signed_out, invite_email: invite_email)}

      membership.user_id == current_user.id ->
        {:ok, assign(socket, :state, :ready)}

      true ->
        {:ok, assign(socket, :state, :wrong_user)}
    end
  end

  defp fetch_membership(membership_id) do
    Membership
    |> Ash.Query.filter(id == ^membership_id)
    |> Ash.Query.load(:workspace)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, membership} -> membership
      _ -> nil
    end
  end

  defp invite_email(%{invite_email: email}) when not is_nil(email), do: email
  defp invite_email(_), do: nil
end
