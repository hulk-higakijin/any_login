# AnyLogin

Generates a development-only account switcher for Phoenix applications.

The generator creates app-specific controller, Plug, and component modules.
It does not modify an existing router or layout automatically.

## Generator

Run the generator from a Phoenix application:

```sh
mix phx.gen.any_login Accounts users
```

The arguments are an existing context module and the users table name. The
generated code expects the context to expose `list_users/0` and `get_user/1`,
and the application's `UserAuth` module to expose `log_in_user/2`.

Useful options:

```sh
mix phx.gen.any_login Accounts users --web MyAppWeb --auth MyAppWeb.UserAuth
```

The generator creates:

- `lib/my_app_web/controllers/any_login_controller.ex`
- `lib/my_app_web/plugs/any_login.ex`
- `lib/my_app_web/components/any_login_component.ex`

After generation, add the generated Plug to the browser pipeline, add the
development-only route, and render the generated component in the root layout.
The generator prints the exact snippets for these steps.

## Generated Integration

For local development, add the package using a path dependency:

```elixir
def deps do
  [
    {:any_login, path: "../any_login"}
  ]
end
```

Then fetch dependencies and run the generator from the Phoenix application:

```sh
mix deps.get
mix phx.gen.any_login Accounts users \
  --web MyAppWeb \
  --auth MyAppWeb.UserAuth
```

The context must expose these functions:

```elixir
Accounts.list_users()
Accounts.get_user(id)
```

Add the generated Plug to the browser pipeline in the router:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug :fetch_current_scope_for_user
  plug MyAppWeb.AnyLogin
end
```

Add the generated route inside a development-only condition:

```elixir
if Application.compile_env(:my_app, :dev_routes, false) do
  scope "/dev", MyAppWeb do
    pipe_through :browser

    post "/account-switcher", AnyLoginController, :switch
  end
end
```

Render the generated component in the root layout:

```heex
<%= if assigns[:any_login_enabled] do %>
  <MyAppWeb.AnyLoginComponent.account_switcher
    users={@any_login_users}
    current_user={@current_scope && @current_scope.user}
    return_to={@any_login_return_to}
  />
<% end %>
```

Start the application normally:

```sh
mix phx.server
```

The switcher appears in the bottom-left corner only when `:dev_routes` is
enabled. The generator does not overwrite an existing router or layout. If
the application already has a manually implemented account switcher, remove
or disable that implementation before adding the generated route to avoid
duplicate routes and UI.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `any_login` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:any_login, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/any_login>.
