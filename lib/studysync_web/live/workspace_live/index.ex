defmodule StudysyncWeb.WorkspaceLive.Index do
  use StudysyncWeb, :live_view

  alias Studysync.Workspaces

  def mount(_params, _session, socket) do
    workspaces =
      Workspaces.list_workspaces!(
        actor: socket.assigns.current_user,
        query: [sort: [inserted_at: :desc]]
      )

    {:ok, assign(socket, workspaces: workspaces, page_title: "Workspaces")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-paper">
      <header class="topbar">
        <div class="flex-1 min-w-0">
          <a href="/" class="font-display text-xl text-ink">
            <em>Study</em>Sync
          </a>
        </div>
        <StudysyncWeb.Layouts.user_menu current_user={@current_user} />
      </header>

      <div class="mx-auto max-w-2xl px-6 py-10">
        <div class="flex items-baseline justify-between mb-8">
          <div>
            <p class="section-label">Your reading groups</p>
            <h1 class="font-display text-4xl text-ink mt-1">Workspaces</h1>
          </div>
          <.link navigate={~p"/workspaces/new"} class="btn btn-primary">
            New workspace
          </.link>
        </div>

        <p :if={@workspaces == []} class="font-serif italic text-ink-soft text-sm py-8 text-center">
          You haven't created or joined any workspaces yet.
        </p>

        <div :if={@workspaces != []} class="card">
          <.link
            :for={workspace <- @workspaces}
            navigate={~p"/workspaces/#{workspace.id}"}
            class="flex items-baseline justify-between px-5 py-4 border-b border-paper-2 last:border-b-0 hover:bg-paper-2/30 transition-colors group"
          >
            <span class="font-display text-xl text-ink group-hover:text-terracotta transition-colors">
              {workspace.name}
            </span>
            <span class="mono-tag num">
              {Calendar.strftime(workspace.inserted_at, "%b %d, %Y")}
            </span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
