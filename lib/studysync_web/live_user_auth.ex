defmodule StudysyncWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use StudysyncWeb, :verified_routes

  alias Studysync.Accounts

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {StudysyncWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, attach_theme_hook(socket)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  # Wires every authenticated LiveView to handle `set_theme` events from the
  # user-menu component. The actor is the signed-in user; on success we
  # patch the local assign so the menu's `data-theme-key` re-renders and the
  # JS hook flips `<html data-theme>` without a full reload.
  defp attach_theme_hook(socket) do
    Phoenix.LiveView.attach_hook(socket, :set_theme, :handle_event, fn
      "set_theme", %{"theme" => theme}, socket ->
        actor = socket.assigns.current_user

        case Accounts.update_theme(actor, %{theme: theme}, actor: actor) do
          {:ok, updated} ->
            {:halt, assign(socket, :current_user, updated)}

          {:error, _reason} ->
            {:halt, socket}
        end

      _event, _params, socket ->
        {:cont, socket}
    end)
  end
end
