defmodule Studysync.Accounts do
  use Ash.Domain,
    otp_app: :studysync

  resources do
    resource Studysync.Accounts.Token
    resource Studysync.Accounts.User
  end
end
