defmodule AnyLogin.Plug do
  @moduledoc """
  Adds the development account switcher assigns to a connection.

  The plug is disabled unless `enabled: true` is passed, so applications can
  keep it in the browser pipeline while compiling the switcher only in dev.
  """

  import Plug.Conn

  alias AnyLogin.Config

  def init(opts), do: opts

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) do
      conn
      |> assign(:any_login_enabled, true)
      |> assign(:any_login_users, Config.list_users())
      |> assign(:any_login_return_to, Phoenix.Controller.current_path(conn))
    else
      assign(conn, :any_login_enabled, false)
    end
  end
end
