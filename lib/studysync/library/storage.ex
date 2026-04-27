defmodule Studysync.Library.Storage do
  @moduledoc """
  Storage abstraction for uploaded files (today: PDFs).

  The dev/test target is local disk (`Storage.Local`). The production target
  is Tigris via S3 (`Storage.S3`, added in a later slice). All callers should
  go through this module — never touch an adapter directly — so swapping the
  prod adapter is a config change.

  Configure the adapter via:

      config :studysync, :storage_adapter, Studysync.Library.Storage.Local
  """

  @callback put(content :: binary, key :: String.t()) :: {:ok, String.t()} | {:error, term}
  @callback url(key :: String.t()) :: String.t()
  @callback delete(key :: String.t()) :: :ok | {:error, term}

  def put(content, key), do: adapter().put(content, key)
  def url(key), do: adapter().url(key)
  def delete(key), do: adapter().delete(key)

  defp adapter do
    Application.fetch_env!(:studysync, :storage_adapter)
  end
end
