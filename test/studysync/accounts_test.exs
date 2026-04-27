defmodule Studysync.AccountsTest do
  use Studysync.DataCase, async: true

  alias Studysync.Accounts

  defp register_user(email) do
    Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "password1234",
      password_confirmation: "password1234"
    })
    |> Ash.create!(authorize?: false)
  end

  describe "update_theme/2" do
    test "defaults to study_sync_default on registration" do
      user = register_user("default@example.com")
      assert user.theme == "study_sync_default"
    end

    test "owner can switch to nord" do
      user = register_user("nord@example.com")

      assert {:ok, updated} = Accounts.update_theme(user, %{theme: "nord"}, actor: user)
      assert updated.theme == "nord"
    end

    test "rejects unknown theme keys" do
      user = register_user("bad@example.com")

      assert {:error, _changeset} =
               Accounts.update_theme(user, %{theme: "synthwave"}, actor: user)
    end

    test "another user cannot change someone else's theme" do
      owner = register_user("owner@example.com")
      attacker = register_user("attacker@example.com")

      assert {:error, _err} =
               Accounts.update_theme(owner, %{theme: "nord"}, actor: attacker)
    end
  end
end
