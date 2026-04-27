defmodule StudysyncWeb.PageControllerTest do
  use StudysyncWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ ~s|data-theme="study_sync_default"|
    assert response =~ "StudySync"
  end
end
