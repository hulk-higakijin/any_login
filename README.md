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
