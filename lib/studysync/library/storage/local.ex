defmodule Studysync.Library.Storage.Local do
  @moduledoc """
  Local-disk storage adapter. Files are written under a base path
  (default `priv/uploads`) keyed by `key`. Used in dev/test — production
  target is Tigris S3.

  The base path is configurable for tests to point at an isolated tmp dir:

      config :studysync, :storage_path, Path.join(System.tmp_dir!(), "studysync-test-uploads")
  """

  @behaviour Studysync.Library.Storage

  @impl true
  def put(content, key) when is_binary(content) and is_binary(key) do
    path = absolute_path(key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    {:ok, key}
  end

  @impl true
  def url(key) when is_binary(key), do: "/uploads/" <> key

  @impl true
  def delete(key) when is_binary(key) do
    case File.rm(absolute_path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      err -> err
    end
  end

  defp absolute_path(key) do
    Path.join([base_path(), key])
  end

  defp base_path do
    Application.get_env(:studysync, :storage_path, "priv/uploads")
  end
end
