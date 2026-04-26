defmodule StudysyncWeb.PageController do
  use StudysyncWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
