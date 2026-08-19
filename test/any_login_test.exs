defmodule AnyLoginTest.Context do
  def get_user(id), do: %{id: id, email: "uuid@example.test"}
end

defmodule AnyLoginTest.Auth do
  def log_in_user(conn, user), do: Plug.Conn.assign(conn, :logged_in_user, user)
end

defmodule AnyLoginTest do
  use ExUnit.Case

  test "switches to a user with a binary primary key" do
    Application.put_env(:any_login, :context, AnyLoginTest.Context)
    Application.put_env(:any_login, :auth, AnyLoginTest.Auth)
    Application.delete_env(:any_login, :repo)

    on_exit(fn ->
      Application.delete_env(:any_login, :context)
      Application.delete_env(:any_login, :auth)
    end)

    conn =
      :post
      |> Plug.Test.conn("/dev/account-switcher")
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> AnyLogin.Controller.switch(%{"user_id" => "550e8400-e29b-41d4-a716-446655440000"})

    assert conn.assigns.logged_in_user.id == "550e8400-e29b-41d4-a716-446655440000"
  end

  test "integrates the shared runtime without generating application modules" do
    path = project_path()
    create_project_fixture(path)
    on_exit(fn -> File.rm_rf!(path) end)

    Mix.Tasks.Phx.Gen.AnyLogin.run(args(path))

    router = read(path, "lib/demo_web/router.ex")
    layout = read(path, "lib/demo_web/components/layouts/root.html.heex")
    config = read(path, "config/dev.exs")

    assert router =~
             "plug AnyLogin.Plug, enabled: Application.compile_env(:demo, :dev_routes, false)"

    assert router =~
             ~s(scope "/dev", AnyLogin do)

    assert router =~ ~s(post "/account-switcher", Controller, :switch)

    assert layout =~ "AnyLogin.Component.account_switcher"
    assert config =~ "repo: Demo.Repo"
    assert config =~ "schema: Demo.Accounts.User"
    assert config =~ "auth: DemoWeb.UserAuth"
    refute File.exists?(Path.join(path, "lib/demo_web/controllers/any_login_controller.ex"))
    refute File.exists?(Path.join(path, "lib/demo_web/plugs/any_login.ex"))
    refute File.exists?(Path.join(path, "lib/demo_web/components/any_login_component.ex"))
    refute read(path, "lib/demo/accounts.ex") =~ "def list_users"
  end

  test "is idempotent" do
    path = project_path()
    create_project_fixture(path)
    on_exit(fn -> File.rm_rf!(path) end)

    Mix.Tasks.Phx.Gen.AnyLogin.run(args(path))
    integrated = project_files(path)

    Mix.Tasks.Phx.Gen.AnyLogin.run(args(path))

    assert project_files(path) == integrated
    assert occurrences(read(path, "lib/demo_web/router.ex"), "plug AnyLogin.Plug") == 1
    assert occurrences(read(path, "lib/demo_web/router.ex"), "post \"/account-switcher\"") == 1
    assert occurrences(read(path, "config/dev.exs"), "config :any_login") == 1

    assert occurrences(
             read(path, "lib/demo_web/components/layouts/root.html.heex"),
             "AnyLogin.Component.account_switcher"
           ) == 1
  end

  test "can print instructions without modifying a project" do
    path = project_path()
    create_project_fixture(path)
    on_exit(fn -> File.rm_rf!(path) end)
    original = project_files(path)

    Mix.Tasks.Phx.Gen.AnyLogin.run(args(path) ++ ["--no-inject"])

    assert project_files(path) == original
  end

  test "preserves an existing account switcher route" do
    path = project_path()
    create_project_fixture(path)
    on_exit(fn -> File.rm_rf!(path) end)

    router_path = Path.join(path, "lib/demo_web/router.ex")

    router =
      router_path
      |> File.read!()
      |> String.replace(
        "    scope \"/dev\" do\n      pipe_through :browser\n    end\n",
        "    scope \"/dev\" do\n      pipe_through :browser\n      post \"/account-switcher\", Elixir.AnyLogin.Controller, :switch\n    end\n"
      )

    File.write!(router_path, router)
    Mix.Tasks.Phx.Gen.AnyLogin.run(args(path))

    integrated_router = File.read!(router_path)
    assert occurrences(integrated_router, "post \"/account-switcher\"") == 1
    assert integrated_router =~ "Elixir.AnyLogin.Controller"
  end

  test "rejects invalid arguments" do
    assert_raise Mix.Error, ~r/Expected a context and a table name/, fn ->
      Mix.Tasks.Phx.Gen.AnyLogin.run(["Accounts"])
    end
  end

  defp args(path) do
    ["Accounts", "users", "--app", "demo", "--web", "DemoWeb", "--path", path]
  end

  defp project_path do
    Path.join(System.tmp_dir!(), "any_login_#{System.unique_integer([:positive])}")
  end

  defp read(path, relative_path), do: File.read!(Path.join(path, relative_path))

  defp project_files(path) do
    %{
      router: read(path, "lib/demo_web/router.ex"),
      layout: read(path, "lib/demo_web/components/layouts/root.html.heex"),
      config: read(path, "config/dev.exs"),
      css: read(path, "assets/css/app.css")
    }
  end

  defp occurrences(source, pattern),
    do: source |> String.split(pattern) |> length() |> Kernel.-(1)

  defp create_project_fixture(path) do
    files = %{
      "config/dev.exs" => "import Config\n\nconfig :demo, dev_routes: true\n",
      "assets/css/app.css" => "@import \"tailwindcss\" source(none);\n",
      "lib/demo/accounts.ex" => """
      defmodule Demo.Accounts do
      end
      """,
      "lib/demo/accounts/user.ex" => """
      defmodule Demo.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :email, :string
        end
      end
      """,
      "lib/demo_web/router.ex" => """
      defmodule DemoWeb.Router do
        use DemoWeb, :router

        pipeline :browser do
          plug :accepts, ["html"]
          plug :fetch_current_scope_for_user
        end

        if Application.compile_env(:demo, :dev_routes) do
          scope "/dev" do
            pipe_through :browser
          end
        end
      end
      """,
      "lib/demo_web/components/layouts/root.html.heex" => """
      <!DOCTYPE html>
      <html>
        <body>
          {@inner_content}
        </body>
      </html>
      """
    }

    Enum.each(files, fn {relative_path, contents} ->
      file = Path.join(path, relative_path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, contents)
    end)
  end
end
