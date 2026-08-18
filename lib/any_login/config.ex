defmodule AnyLogin.Config do
  @moduledoc false

  def context do
    Application.fetch_env!(:any_login, :context)
  end

  def auth do
    Application.fetch_env!(:any_login, :auth)
  end

  def list_users do
    apply(context(), :list_users, [])
  end

  def get_user(id) do
    apply(context(), :get_user, [id])
  end

  def log_in_user(conn, user) do
    apply(auth(), :log_in_user, [conn, user])
  end
end
