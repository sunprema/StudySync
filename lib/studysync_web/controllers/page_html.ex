defmodule StudysyncWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use StudysyncWeb, :html

  embed_templates "page_html/*"

  @doc """
  Two-letter initials for a user, derived from the email local-part.
  Falls back to "·" when no user/email is present.
  """
  def initials(nil), do: "·"
  def initials(%{email: email}), do: initials(email)

  def initials(%Ash.CiString{} = email), do: email |> to_string() |> initials()

  def initials(email) when is_binary(email) do
    email
    |> String.split("@", parts: 2)
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end
end
