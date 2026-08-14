defmodule AnyLoginTest do
  use ExUnit.Case

  test "generates an account switcher integration" do
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
      path
    ])

    controller = File.read!(Path.join(path, "lib/demo_web/controllers/any_login_controller.ex"))
    plug = File.read!(Path.join(path, "lib/demo_web/plugs/any_login.ex"))
    component = File.read!(Path.join(path, "lib/demo_web/components/any_login_component.ex"))

    assert controller =~ "defmodule DemoWeb.AnyLoginController"
    assert controller =~ "Demo.Accounts.get_user(id)"
    assert plug =~ "Demo.Accounts.list_users()"
    assert plug =~ "@dev_routes Application.compile_env(:demo, :dev_routes, false)"
    assert component =~ "def account_switcher(assigns)"

    assert Code.string_to_quoted!(controller)
    assert Code.string_to_quoted!(plug)
    assert Code.string_to_quoted!(component)
  end

  test "rejects invalid arguments" do
    assert_raise Mix.Error, ~r/Expected a context and a table name/, fn ->
      Mix.Tasks.Phx.Gen.AnyLogin.run(["Accounts"])
    end
  end
end
