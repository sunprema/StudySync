defmodule Studysync.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Studysync.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:studysync, :token_signing_secret)
  end
end
