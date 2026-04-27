defmodule StudysyncWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use StudysyncWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={static_url(StudysyncWeb.Endpoint, ~p"/images/logo.svg")} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Resolves the active theme key from layout assigns.

  Falls back to "study_sync_default" when there is no signed-in user (e.g.
  the landing page, sign-in screen) or when the attribute is absent.
  """
  def user_theme(%{current_user: %{theme: theme}}) when is_binary(theme), do: theme
  def user_theme(_), do: "study_sync_default"

  @doc """
  Avatar + settings dropdown for an authenticated user. Click the avatar to
  open a menu with the theme picker and sign-out link.

  Theme changes apply optimistically in the browser via the `Theme` JS hook
  (sets `data-theme` on `<html>` immediately) and are persisted via the
  `Studysync.Accounts.update_theme/2` action triggered by the LiveView
  attached to whichever page rendered the menu.
  """
  attr :current_user, :map, required: true
  attr :class, :string, default: nil

  def user_menu(assigns) do
    ~H"""
    <div
      id="user-menu"
      phx-hook="Theme"
      data-theme-key={user_theme(%{current_user: @current_user})}
      class={["relative", @class]}
    >
      <details class="group">
        <summary
          aria-label="Open settings menu"
          class={[
            "list-none cursor-pointer select-none",
            "w-9 h-9 rounded-full flex items-center justify-center",
            "bg-paper-2 text-ink-soft border border-paper-2",
            "font-mono text-[11px] uppercase tracking-widest",
            "hover:border-terracotta hover:text-terracotta transition-colors"
          ]}
        >
          {avatar_initials(@current_user.email)}
        </summary>

        <div
          role="menu"
          class={[
            "absolute right-0 mt-2 w-64 z-50",
            "bg-paper border border-paper-2 shadow-sm rounded-sm",
            "p-4 space-y-4"
          ]}
        >
          <div>
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
              Signed in as
            </p>
            <p class="font-serif text-ink text-sm truncate mt-1">{@current_user.email}</p>
          </div>

          <div>
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft mb-2">
              Theme
            </p>

            <div class="grid grid-cols-2 gap-2">
              <.theme_option
                value="study_sync_default"
                label="Margin Notes"
                active={user_theme(%{current_user: @current_user}) == "study_sync_default"}
              />
              <.theme_option
                value="nord"
                label="Nord"
                active={user_theme(%{current_user: @current_user}) == "nord"}
              />
            </div>
          </div>

          <div class="border-t border-paper-2 pt-3">
            <.link
              href={~p"/sign-out"}
              method="get"
              class="font-mono text-[11px] uppercase tracking-widest text-ink-soft hover:text-terracotta transition-colors"
            >
              Sign out
            </.link>
          </div>
        </div>
      </details>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp theme_option(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_theme"
      phx-value-theme={@value}
      aria-pressed={to_string(@active)}
      class={[
        "px-3 py-2 text-left rounded-sm border transition-colors cursor-pointer",
        if(@active,
          do: "border-terracotta text-terracotta bg-paper",
          else: "border-paper-2 text-ink-soft hover:border-terracotta hover:text-terracotta"
        )
      ]}
    >
      <span class="font-mono text-[10px] uppercase tracking-widest block">
        {@label}
      </span>
    </button>
    """
  end

  defp avatar_initials(nil), do: "·"

  defp avatar_initials(email) do
    email
    |> to_string()
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
