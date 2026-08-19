defmodule AnyLogin.Config do
  @moduledoc false

  def auth do
    Application.fetch_env!(:any_login, :auth)
  end

  def list_users do
    case repo() do
      nil -> apply(Application.fetch_env!(:any_login, :context), :list_users, [])
      repo -> apply(repo, :all, [schema()])
    end
  end

  def get_user(id) do
    case repo() do
      nil -> apply(Application.fetch_env!(:any_login, :context), :get_user, [id])
      repo -> apply(repo, :get, [schema(), id])
    end
  end

  def log_in_user(conn, user) do
    apply(auth(), :log_in_user, [conn, user])
  end

  defp repo, do: Application.get_env(:any_login, :repo)

  defp schema, do: Application.fetch_env!(:any_login, :schema)
end
