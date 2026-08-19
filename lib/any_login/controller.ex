defmodule AnyLogin.Controller do
  @moduledoc false

  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias AnyLogin.Config

  def switch(conn, %{"user_id" => user_id} = params) do
    with user when not is_nil(user) <- Config.get_user(user_id) do
      conn
      |> put_session(:user_return_to, safe_return_to(params["return_to"]))
      |> put_flash(:info, "Logged in as #{user_label(user)}.")
      |> Config.log_in_user(user)
    else
      _ -> invalid_account(conn)
    end
  end

  def switch(conn, _params), do: invalid_account(conn)

  defp invalid_account(conn) do
    conn
    |> put_flash(:error, "The selected development account is invalid.")
    |> redirect(to: "/")
  end

  defp user_label(user), do: Map.get(user, :email, user.id)

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    else
      "/"
    end
  end

  defp safe_return_to(_path), do: "/"
end
