defmodule Studysync.Workspaces do
  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  resources do
    resource Studysync.Workspaces.Workspace do
      define :create_workspace, action: :create, args: [:name]
      define :list_workspaces, action: :read
      define :get_workspace, action: :read, get_by: [:id]
    end

    resource Studysync.Workspaces.Membership do
      define :list_memberships, action: :read
      define :invite_member, action: :invite, args: [:workspace_id, :email]
      define :accept_invite, action: :accept
    end
  end
end
