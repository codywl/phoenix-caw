defmodule CahWeb.PageController do
  use CahWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
