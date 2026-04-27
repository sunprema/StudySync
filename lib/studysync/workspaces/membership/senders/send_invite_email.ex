defmodule Studysync.Workspaces.Membership.Senders.SendInviteEmail do
  @moduledoc """
  Delivers a workspace invitation email containing a signed-token URL pointing
  at the accept route. Stateless — the token carries the membership id and is
  verified on click; no DB column for the token is needed.
  """

  use StudysyncWeb, :verified_routes

  import Swoosh.Email

  alias Studysync.Mailer

  @token_salt "workspace invite"
  @token_max_age 60 * 60 * 24 * 14

  @doc """
  Builds and delivers the email. Returns `{:ok, _}` from Swoosh on success.
  """
  def send(membership, workspace, recipient_email) do
    token = sign_token(membership.id)
    accept_url = url(~p"/invites/#{token}")

    new()
    |> from({"StudySync", "noreply@studysync.local"})
    |> to(to_string(recipient_email))
    |> subject("You're invited to #{workspace.name}")
    |> html_body(html_body_for(workspace, accept_url))
    |> text_body(text_body_for(workspace, accept_url))
    |> Mailer.deliver()
  end

  @doc "Sign a membership id into an opaque token."
  def sign_token(membership_id) do
    Phoenix.Token.sign(StudysyncWeb.Endpoint, @token_salt, membership_id)
  end

  @doc """
  Verify a token and return `{:ok, membership_id}` or `{:error, reason}`.
  Reasons: `:invalid`, `:expired`.
  """
  def verify_token(token) do
    Phoenix.Token.verify(StudysyncWeb.Endpoint, @token_salt, token, max_age: @token_max_age)
  end

  defp html_body_for(workspace, accept_url) do
    """
    <p>You've been invited to join <strong>#{workspace.name}</strong> on StudySync.</p>
    <p><a href="#{accept_url}">Accept invitation</a></p>
    <p style="color:#5C5750;font-size:12px">If you weren't expecting this, you can ignore the email.</p>
    """
  end

  defp text_body_for(workspace, accept_url) do
    """
    You've been invited to join #{workspace.name} on StudySync.

    Accept: #{accept_url}

    If you weren't expecting this, you can ignore the email.
    """
  end
end
