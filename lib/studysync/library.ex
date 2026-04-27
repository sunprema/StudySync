defmodule Studysync.Library do
  use Ash.Domain,
    otp_app: :studysync,
    extensions: [AshPhoenix]

  resources do
    resource Studysync.Library.Resource do
      define :list_resources, action: :read
      define :get_resource, action: :read, get_by: [:id]
      define :upload_resource, action: :upload, args: [:workspace_id, :title, :upload]
    end
  end
end
