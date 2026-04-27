# Slice 15 perf-pass benchmark — measures the hot paths described in
# CLAUDE.md §6. Run with `MIX_ENV=dev mix run priv/scripts/perf_pass.exs`.
#
# The script:
#   1. Provisions an isolated workspace + resource + N annotations.
#   2. Measures annotation create latency end-to-end (Ash action,
#      including policy + PubSub broadcast) for a fresh batch.
#   3. Measures the lazy-load query for a single page.
#   4. Measures the lightweight index load for the whole resource.
#   5. Measures the PubSub broadcast fan-out (zero subscribers — pure
#      Phoenix.PubSub overhead).
#
# Output is printed as a table; copy into PERFORMANCE.md when run.

alias Studysync.Accounts
alias Studysync.Annotations
alias Studysync.Library
alias Studysync.Workspaces

defmodule Bench do
  def percentile(values, p) do
    sorted = Enum.sort(values)
    idx = max(round(p * length(sorted)) - 1, 0)
    Enum.at(sorted, idx)
  end

  def time(fun) do
    {micros, value} = :timer.tc(fun)
    {micros / 1_000.0, value}
  end

  def stats(label, durations_ms) do
    sorted = Enum.sort(durations_ms)
    n = length(sorted)
    avg = (Enum.sum(sorted) / n) |> Float.round(2)
    p50 = percentile(sorted, 0.50) |> Float.round(2)
    p95 = percentile(sorted, 0.95) |> Float.round(2)
    p99 = percentile(sorted, 0.99) |> Float.round(2)
    min = sorted |> List.first() |> Float.round(2)
    max = sorted |> List.last() |> Float.round(2)

    IO.puts(
      String.pad_trailing(label, 36) <>
        "n=#{n} min=#{min}ms p50=#{p50}ms p95=#{p95}ms p99=#{p99}ms max=#{max}ms avg=#{avg}ms"
    )
  end
end

# --- setup ------------------------------------------------------------

email = "perf-#{System.unique_integer([:positive])}@example.com"

user =
  Accounts.User
  |> Ash.Changeset.for_create(:register_with_password, %{
    email: email,
    password: "password1234",
    password_confirmation: "password1234"
  })
  |> Ash.create!(authorize?: false)

workspace = Workspaces.create_workspace!("Perf Pass", actor: user)

# Use a small valid PDF — same one the test suite uses.
pdf = """
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R >> endobj
4 0 obj << /Type /Page /Parent 2 0 R >> endobj
5 0 obj << /Type /Page /Parent 2 0 R >> endobj
trailer << /Root 1 0 R >>
%%EOF
"""

resource =
  Library.upload_resource!(
    workspace.id,
    "Perf Resource",
    %{content: pdf, filename: "perf.pdf"},
    actor: user
  )

IO.puts("Resource: #{resource.id} (#{resource.page_count} pages)")
IO.puts("")

# --- 1. annotation create latency ------------------------------------

create_durations =
  for i <- 1..200 do
    page = rem(i, 3) + 1

    {dur, _} =
      Bench.time(fn ->
        Annotations.create_comment!(
          resource.id,
          page,
          %{"x" => 0.1, "y" => 0.1, "width" => 0.2, "height" => 0.05},
          "snippet #{i}",
          "body #{i}",
          actor: user
        )
      end)

    dur
  end

# --- 2. lazy-load (single page) --------------------------------------

page_load_durations =
  for _ <- 1..50 do
    {dur, _rows} =
      Bench.time(fn ->
        Annotations.list_annotations_for_pages(resource.id, [1], actor: user)
      end)

    dur
  end

# --- 3. lightweight index --------------------------------------------

index_durations =
  for _ <- 1..50 do
    {dur, _rows} =
      Bench.time(fn ->
        Annotations.list_annotation_index(resource.id, actor: user)
      end)

    dur
  end

# --- 4. PubSub broadcast fan-out (no subscribers) --------------------

broadcast_durations =
  for _ <- 1..200 do
    annotation_id = Ash.UUID.generate()

    {dur, _} =
      Bench.time(fn ->
        Studysync.Annotations.PubSub.broadcast_annotation_created(
          resource.id,
          annotation_id
        )
      end)

    dur
  end

IO.puts("=== Results ===")
Bench.stats("annotation_create (Ash + broadcast)", create_durations)
Bench.stats("page_load (1 page, full bodies)", page_load_durations)
Bench.stats("index_load (whole resource, stub)", index_durations)
Bench.stats("pubsub_broadcast (0 subscribers)", broadcast_durations)
IO.puts("")
IO.puts("Total annotations now on resource: #{length(index_durations)} reads complete.")
