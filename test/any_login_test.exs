defmodule AnyLoginTest do
  use ExUnit.Case

  test "generates an account switcher integration" do
    path = Path.join(System.tmp_dir!(), "any_login_#{System.unique_integer([:positive])}")
    create_project_fixture(path)

    on_exit(fn -> File.rm_rf!(path) end)

    args = [
      "Accounts",
      "users",
      "--app",
      "demo",
      "--web",
      "DemoWeb",
      "--path",
      path
    ]

    Mix.Tasks.Phx.Gen.AnyLogin.run(args)

    controller = File.read!(Path.join(path, "lib/demo_web/controllers/any_login_controller.ex"))
    plug = File.read!(Path.join(path, "lib/demo_web/plugs/any_login.ex"))
    component = File.read!(Path.join(path, "lib/demo_web/components/any_login_component.ex"))
    router = File.read!(Path.join(path, "lib/demo_web/router.ex"))
    layout = File.read!(Path.join(path, "lib/demo_web/components/layouts/root.html.heex"))
    context = File.read!(Path.join(path, "lib/demo/accounts.ex"))

    assert controller =~ "defmodule DemoWeb.AnyLoginController"
    assert controller =~ "Accounts.get_user(id)"
    assert plug =~ "Accounts.list_users()"
    assert plug =~ "@dev_routes Application.compile_env(:demo, :dev_routes, false)"
    assert component =~ "def account_switcher(assigns)"
    assert component =~ ~s(aria-label="Open development account switcher")
    assert component =~ "data-any-login-switcher-toggle"
    assert component =~ "data-any-login-switcher-panel"
    assert component =~ "document.addEventListener(\"click\""
    assert component =~ "if (!switcher.contains(event.target)) close();"
    assert component =~ "panel.hidden = !opening"
    assert component =~ "bg-orange-400"
    assert router =~ "plug DemoWeb.AnyLogin"
    assert router =~ ~s(scope "/dev", DemoWeb do)
    assert router =~ ~s(post "/account-switcher", AnyLoginController, :switch)
    assert layout =~ "DemoWeb.AnyLoginComponent.account_switcher"
    assert context =~ "def list_users, do: Demo.Repo.all(Demo.Accounts.User)"
    assert context =~ "def get_user(id), do: Demo.Repo.get(Demo.Accounts.User, id)"

    assert Code.string_to_quoted!(controller)
    assert Code.string_to_quoted!(plug)
    assert Code.string_to_quoted!(component)
    assert Code.string_to_quoted!(router)
    assert Code.string_to_quoted!(context)

    integrated_router = router
    integrated_layout = layout
    integrated_context = context

    Mix.Tasks.Phx.Gen.AnyLogin.run(args ++ ["--force"])

    assert File.read!(Path.join(path, "lib/demo_web/router.ex")) == integrated_router

    assert File.read!(Path.join(path, "lib/demo_web/components/layouts/root.html.heex")) ==
             integrated_layout

    assert File.read!(Path.join(path, "lib/demo/accounts.ex")) == integrated_context

    assert occurrences(
             File.read!(Path.join(path, "lib/demo_web/router.ex")),
             "plug DemoWeb.AnyLogin"
           ) ==
             1

    assert occurrences(
             File.read!(Path.join(path, "lib/demo_web/router.ex")),
             ~s(post "/account-switcher", AnyLoginController, :switch)
           ) == 1

    assert occurrences(
             File.read!(Path.join(path, "lib/demo_web/components/layouts/root.html.heex")),
             "DemoWeb.AnyLoginComponent.account_switcher"
           ) == 1

    assert occurrences(File.read!(Path.join(path, "lib/demo/accounts.ex")), "def list_users") == 1

    assert occurrences(File.read!(Path.join(path, "lib/demo/accounts.ex")), "def get_user(id)") ==
             1
  end

  test "can generate files without modifying a project" do
    path = Path.join(System.tmp_dir!(), "any_login_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)

    on_exit(fn -> File.rm_rf!(path) end)

    Mix.Tasks.Phx.Gen.AnyLogin.run([
      "Accounts",
      "users",
      "--app",
      "demo",
      "--web",
      "DemoWeb",
      "--path",
      path,
      "--no-inject"
    ])

    assert File.exists?(Path.join(path, "lib/demo_web/controllers/any_login_controller.ex"))
    refute File.exists?(Path.join(path, "lib/demo_web/router.ex"))
  end

  test "preserves an existing fully qualified account switcher route" do
    path = Path.join(System.tmp_dir!(), "any_login_#{System.unique_integer([:positive])}")
    create_project_fixture(path)

    on_exit(fn -> File.rm_rf!(path) end)

    router_path = Path.join(path, "lib/demo_web/router.ex")

    router =
      router_path
      |> File.read!()
      |> String.replace(
        "    scope \"/dev\" do\n      pipe_through :browser\n    end\n",
        "    scope \"/dev\" do\n      pipe_through :browser\n      " <>
          "post \"/account-switcher\", DemoWeb.AnyLoginController, :switch\n    end\n"
      )

    File.write!(router_path, router)

    Mix.Tasks.Phx.Gen.AnyLogin.run([
      "Accounts",
      "users",
      "--app",
      "demo",
      "--web",
      "DemoWeb",
      "--path",
      path
    ])

    integrated_router = File.read!(router_path)

    assert occurrences(integrated_router, "post \"/account-switcher\"") == 1
    assert integrated_router =~ "DemoWeb.AnyLoginController"
    refute integrated_router =~ ~s(scope "/dev", DemoWeb do)
  end

  test "rejects invalid arguments" do
    assert_raise Mix.Error, ~r/Expected a context and a table name/, fn ->
      Mix.Tasks.Phx.Gen.AnyLogin.run(["Accounts"])
    end
  end

  defp create_project_fixture(path) do
    files = %{
      "lib/demo/accounts.ex" => """
      defmodule Demo.Accounts do
        alias Demo.Repo

        def get_user!(id), do: Repo.get!(Demo.Accounts.User, id)
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

  defp occurrences(source, pattern) do
    source
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end
end
