defmodule StudysyncWeb.PdfLive.Show do
  use StudysyncWeb, :live_view

  alias Studysync.Library

  def mount(%{"workspace_id" => workspace_id, "id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Library.get_resource(id, actor: actor) do
      {:ok, resource}
      when not is_nil(resource) and resource.workspace_id == workspace_id ->
        {:ok,
         socket
         |> assign(:resource, resource)
         |> assign(:workspace_id, workspace_id)
         |> assign(:file_url, ~p"/resources/#{resource.id}/file")
         |> assign(:page_title, resource.title)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Resource not found.")
         |> push_navigate(to: ~p"/workspaces/#{workspace_id}/library")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-screen w-full bg-paper text-ink overflow-hidden">
      <.chapter_rail />

      <main class="flex-1 min-w-0 flex flex-col">
        <header class="flex items-baseline justify-between border-b border-paper-2 px-8 py-4">
          <div class="min-w-0">
            <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
              <.link
                navigate={~p"/workspaces/#{@workspace_id}/library"}
                class="hover:text-terracotta"
              >
                Library
              </.link>
              <span> ·  Reader</span>
            </p>
            <h1 class="font-display text-3xl text-ink truncate mt-1">{@resource.title}</h1>
          </div>
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft num shrink-0">
            <span class="num">{@resource.page_count}</span> pages
          </p>
        </header>

        <div id="pdf-canvas" class="flex-1 overflow-hidden">
          <.svelte
            name="PdfCanvasRenderer"
            props={%{file_url: @file_url, total_pages: @resource.page_count}}
            socket={@socket}
          />
        </div>
      </main>

      <aside class="w-[360px] shrink-0 bg-paper-2 border-l border-paper-2 flex flex-col">
        <header class="px-6 py-4 border-b border-paper-2/60">
          <p class="font-mono text-[10px] uppercase tracking-widest text-ink-soft">
            Margin · <span class="num">0</span> notes
          </p>
        </header>
        <div class="flex-1 overflow-y-auto px-6 py-6">
          <p class="font-serif italic text-ink-soft">
            No annotations yet. Slice 4 will let you select text and add a comment.
          </p>
        </div>
      </aside>
    </div>
    """
  end
end
