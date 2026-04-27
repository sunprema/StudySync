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
    <div class="mx-auto max-w-xl px-8 py-16">
      <p class="font-mono text-xs uppercase tracking-widest text-ink-soft">Invitation</p>

      <%= case @state do %>
        <% :invalid_token -> %>
          <h1 class="font-display text-4xl text-ink mt-1">Invitation expired</h1>
          <p class="font-serif italic text-ink-soft mt-6">
            This invite link is invalid or older than 14 days. Ask the workspace admin to resend.
          </p>
        <% :missing -> %>
          <h1 class="font-display text-4xl text-ink mt-1">Invitation not found</h1>
          <p class="font-serif italic text-ink-soft mt-6">
            This invitation no longer exists.
          </p>
        <% :already_active -> %>
          <h1 class="font-display text-4xl text-ink mt-1">Already a member</h1>
          <p class="font-serif italic text-ink-soft mt-6">
            You're already in <strong>{@workspace.name}</strong>.
          </p>
          <.link
            navigate={~p"/workspaces/#{@workspace.id}"}
            class="font-mono text-xs uppercase tracking-widest text-terracotta mt-6 inline-block"
          >
            Go to workspace →
          </.link>
        <% :signed_out -> %>
          <h1 class="font-display text-4xl text-ink mt-1">
            You're invited to {@workspace.name}
          </h1>
          <p class="font-serif italic text-ink-soft mt-6">
            Sign in or create an account with <strong>{to_string(@invite_email)}</strong> to accept.
          </p>
          <div class="mt-8 flex gap-4">
            <.link navigate={~p"/sign-in"} class="btn btn-primary">Sign in</.link>
            <.link
              navigate={~p"/register"}
              class="font-mono text-xs uppercase tracking-widest text-ink-soft"
            >
              Create account →
            </.link>
          </div>
        <% :wrong_user -> %>
          <h1 class="font-display text-4xl text-ink mt-1">Not your invitation</h1>
          <p class="font-serif italic text-ink-soft mt-6">
            This invitation was sent to a different email. Sign in as that user to accept.
          </p>
        <% :ready -> %>
          <h1 class="font-display text-4xl text-ink mt-1">
            Join {@workspace.name}
          </h1>
          <p class="font-serif italic text-ink-soft mt-6">
            You've been invited to join this workspace.
          </p>
          <button type="button" phx-click="accept" class="btn btn-primary mt-8">
            Accept invitation
          </button>
      <% end %>
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
