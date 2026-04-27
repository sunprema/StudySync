defmodule Studysync.Library.PdfPageCount do
  @moduledoc """
  Approximate PDF page count via a regex over the raw bytes.

  This counts occurrences of `/Type /Page` (excluding `/Pages` and `/PageMode`)
  in the binary. It works for uncompressed PDFs and most PDFs in the wild,
  but cannot read pages hidden inside compressed object streams. For Slice 2
  this is sufficient — Slice 3's PDF.js render is the authoritative count.

  Always returns at least 1 (a PDF must have at least one page).
  """

  def count(binary) when is_binary(binary) do
    binary
    |> :binary.matches("/Type")
    |> Enum.count(fn {start, _len} ->
      tail = :binary.part(binary, start, min(byte_size(binary) - start, 32))
      Regex.match?(~r{^/Type\s*/Page(?![sR/A-Za-z])}, tail)
    end)
    |> max(1)
  end
end
