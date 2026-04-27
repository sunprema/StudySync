defmodule Studysync.Accounts do
  use Ash.Domain,
    otp_app: :studysync

  resources do
    resource Studysync.Accounts.Token

    resource Studysync.Accounts.User do
      define :update_theme, action: :update_theme
    end
  end
end
