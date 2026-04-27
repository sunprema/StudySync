defmodule StudysyncWeb.WorkspaceLive.New do
  use StudysyncWeb, :live_view

  alias Studysync.Workspaces

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: build_form(socket), page_title: "New workspace")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl px-8 py-12">
      <header class="border-b border-paper-2 pb-6 mb-10">
        <p class="font-mono text-xs uppercase tracking-widest text-ink-soft">New</p>
        <h1 class="font-display text-5xl text-ink mt-1">A new workspace</h1>
      </header>

      <.form
        for={@form}
        id="workspace-form"
        phx-change="validate"
        phx-submit="submit"
        class="space-y-6"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="The Reading Group"
          autofocus
          required
        />

        <div class="flex gap-3">
          <button type="submit" class="btn btn-primary">Create workspace</button>
          <.link navigate={~p"/workspaces"} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>
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
