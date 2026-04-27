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
    <div class="mx-auto max-w-3xl px-8 py-12">
      <header class="flex items-baseline justify-between border-b border-paper-2 pb-6 mb-10">
        <div>
          <p class="font-mono text-xs uppercase tracking-widest text-ink-soft">Library</p>
          <h1 class="font-display text-5xl text-ink mt-1">Workspaces</h1>
        </div>
        <.link navigate={~p"/workspaces/new"} class="btn btn-primary">
          New workspace
        </.link>
      </header>

      <p :if={@workspaces == []} class="font-serif italic text-ink-soft">
        You haven't created or joined any workspaces yet.
      </p>

      <ul :if={@workspaces != []} class="divide-y divide-paper-2">
        <li :for={workspace <- @workspaces} class="py-5">
          <.link
            navigate={~p"/workspaces/#{workspace.id}"}
            class="flex items-baseline justify-between hover:text-terracotta transition-colors"
          >
            <span class="font-display text-2xl">{workspace.name}</span>
            <span class="font-mono text-xs uppercase tracking-widest text-ink-soft num">
              {Calendar.strftime(workspace.inserted_at, "%b %d, %Y")}
            </span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
