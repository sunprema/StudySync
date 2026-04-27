defmodule StudysyncWeb.LibraryComponents do
  @moduledoc """
  Phoenix components for the workspace library — Direction 01: Margin Notes.

  Naming and styling follow CLAUDE.md §5. New components should live here
  rather than in `core_components.ex` (which holds Phoenix-generated
  primitives like inputs and tables).
  """
  use Phoenix.Component

  attr :resource, :map, required: true
  attr :uploader_email, :string, default: nil

  def resource_card(assigns) do
    ~H"""
    <article
      id={"resource-#{@resource.id}"}
      class="border-b border-paper-2 py-5 flex items-baseline justify-between gap-6"
    >
      <div class="min-w-0">
        <h3 class="font-display text-2xl text-ink truncate">{@resource.title}</h3>
        <p class="font-mono text-xs uppercase tracking-widest text-ink-soft mt-2">
          <span class="num">{@resource.page_count}</span>
          pages · {format_date(@resource.inserted_at)}<span :if={@uploader_email}> · {@uploader_email}</span>
        </p>
      </div>
    </article>
    """
  end

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %d, %Y")
end
