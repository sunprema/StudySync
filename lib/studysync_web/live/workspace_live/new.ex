defmodule StudysyncWeb.WorkspaceLive.New do
  use StudysyncWeb, :live_view

  alias Studysync.Workspaces

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: build_form(socket), page_title: "New workspace")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-paper">
      <header class="topbar">
        <a href="/" class="font-display text-xl text-ink"><em>Study</em>Sync</a>
        <div class="ml-auto flex items-center gap-3">
          <.link navigate={~p"/workspaces"} class="btn btn-ghost btn-sm">Workspaces</.link>
        </div>
      </header>

      <div class="mx-auto max-w-md px-6 py-12">
        <p class="section-label mb-1">Create</p>
        <h1 class="font-display text-4xl text-ink mb-8">A new workspace</h1>

        <div class="card">
          <div class="card-pad">
            <.form
              for={@form}
              id="workspace-form"
              phx-change="validate"
              phx-submit="submit"
              class="space-y-5"
            >
              <.input
                field={@form[:name]}
                type="text"
                label="Workspace name"
                placeholder="The Reading Group"
                autofocus
                required
              />

              <div class="flex gap-3 pt-2">
                <button type="submit" class="btn btn-primary">Create workspace</button>
                <.link navigate={~p"/workspaces"} class="btn btn-ghost">Cancel</.link>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("submit", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> put_flash(:info, "Workspace created.")
         |> push_navigate(to: ~p"/workspaces/#{workspace.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp build_form(socket) do
    Workspaces.Workspace
    |> AshPhoenix.Form.for_create(:create, actor: socket.assigns.current_user)
    |> to_form()
  end
end
