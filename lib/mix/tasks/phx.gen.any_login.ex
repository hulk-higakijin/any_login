defmodule Mix.Tasks.Phx.Gen.AnyLogin do
  @shortdoc "Generates a development-only account switcher"

  @moduledoc """
  Generates a development-only account switcher for a Phoenix application.

      mix phx.gen.any_login Accounts users

  The first argument is the existing context module and the second argument is
  the users table name. The generated code expects the context to expose
  `list_users/0` and `get_user/1`, and the application's `UserAuth` module to
  expose `log_in_user/2`.
  """
  use Mix.Task

  alias Mix.Generator

  @switches [
    app: :string,
    auth: :string,
    force: :boolean,
    path: :string,
    web: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    {context, table} = parse_arguments!(positional)
    app = opts[:app] || Mix.Project.config()[:app] |> to_string()
    app_module = Macro.camelize(app)
    web_module = opts[:web] || "#{app_module}Web"
    auth_module = opts[:auth] || "#{web_module}.UserAuth"
    context_module = qualify_context(context, app_module)
    root = opts[:path] || File.cwd!()

    binding = [
      app_module: app_module,
      auth_module: auth_module,
      context_module: context_module,
      table: table,
      web_module: web_module
    ]

    files = generated_files(binding, root)

    Enum.each(files, fn {path, contents} ->
      Generator.create_file(path, contents, force: opts[:force] == true)
    end)

    print_instructions(binding)
  end

  defp parse_arguments!([context, table]),
    do: {validate_context!(context), validate_table!(table)}

  defp parse_arguments!(_args) do
    Mix.raise("""
    Expected a context and a table name.

        mix phx.gen.any_login Accounts users
    """)
  end

  defp validate_context!(context) do
    if Regex.match?(~r/^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$/, context) do
      context
    else
      Mix.raise("Invalid context module: #{inspect(context)}")
    end
  end

  defp validate_table!(table) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, table) do
      table
    else
      Mix.raise("Invalid table name: #{inspect(table)}")
    end
  end

  defp qualify_context(context, app_module) do
    if String.starts_with?(context, "#{app_module}.") do
      context
    else
      "#{app_module}.#{context}"
    end
  end

  defp generated_files(binding, root) do
    web_path = binding[:web_module] |> Macro.underscore()

    [
      {Path.join(root, "lib/#{web_path}/controllers/any_login_controller.ex"),
       controller_template(binding)},
      {Path.join(root, "lib/#{web_path}/plugs/any_login.ex"), plug_template(binding)},
      {Path.join(root, "lib/#{web_path}/components/any_login_component.ex"),
       component_template(binding)}
    ]
  end

  defp controller_template(binding) do
    """
    defmodule #{binding[:web_module]}.AnyLoginController do
      use #{binding[:web_module]}, :controller

      alias #{binding[:context_module]}
      alias #{binding[:auth_module]}

      def switch(conn, %{"user_id" => user_id} = params) do
        with {id, ""} <- Integer.parse(user_id),
             user when not is_nil(user) <- #{binding[:context_module]}.get_user(id) do
          conn
          |> put_session(:user_return_to, safe_return_to(params["return_to"]))
          |> put_flash(:info, "Logged in as \#{user_label(user)}.")
          |> UserAuth.log_in_user(user)
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
    """
    |> Code.format_string!()
  end

  defp plug_template(binding) do
    """
    defmodule #{binding[:web_module]}.AnyLogin do
      @moduledoc \"\"\"
      Development-only assigns for the AnyLogin account switcher.

      Add `plug #{binding[:web_module]}.AnyLogin` to the browser pipeline.
      \"\"\"

      @dev_routes Application.compile_env(:#{binding[:app_module] |> Macro.underscore()}, :dev_routes, false)

      import Plug.Conn

      alias #{binding[:context_module]}

      def init(opts), do: opts

      def call(conn, _opts) do
        if @dev_routes do
          conn
          |> assign(:any_login_enabled, true)
          |> assign(:any_login_users, #{binding[:context_module]}.list_users())
          |> assign(:any_login_return_to, Phoenix.Controller.current_path(conn))
        else
          assign(conn, :any_login_enabled, false)
        end
      end
    end
    """
    |> Code.format_string!()
  end

  defp component_template(binding) do
    """
    defmodule #{binding[:web_module]}.AnyLoginComponent do
      use #{binding[:web_module]}, :html

      attr :users, :list, required: true
      attr :current_user, :map, default: nil
      attr :return_to, :string, default: "/"
      attr :switch_path, :string, default: "/dev/account-switcher"
      attr :logout_path, :string, default: "/users/log-out"

      def account_switcher(assigns) do
        ~H\"\"\"
        <section id="any-login-switcher" class="fixed bottom-4 left-4 z-50 w-80 rounded-xl border bg-base-100 p-4 shadow-xl">
          <p class="mb-3 text-sm font-semibold">Development account</p>
          <form action={@switch_path} method="post" id="any-login-switcher-form" class="space-y-3">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="return_to" value={@return_to} />
            <label for="any-login-user-id" class="sr-only">Account</label>
            <select id="any-login-user-id" name="user_id" required class="w-full rounded-lg border p-2">
              <option value="">Select an account</option>
              <%= for user <- @users do %>
                <option value={user.id} selected={@current_user && @current_user.id == user.id}>
                  {Map.get(user, :email, user.id)}
                </option>
              <% end %>
            </select>
            <button type="submit" class="w-full rounded-lg bg-primary px-3 py-2 text-sm text-primary-content">
              Switch account
            </button>
          </form>
          <%= if @current_user do %>
            <div class="mt-3 border-t pt-3 text-sm">
              <span>{Map.get(@current_user, :email, @current_user.id)}</span>
              <.link href={@logout_path} method="delete" class="ml-2 underline">Log out</.link>
            </div>
          <% end %>
        </section>
        \"\"\"
      end
    end
    """
    |> Code.format_string!()
  end

  defp print_instructions(binding) do
    Mix.shell().info("""

    AnyLogin files generated for #{binding[:context_module]}.#{binding[:table]}.

    Add this to your browser pipeline:

        plug #{binding[:web_module]}.AnyLogin

    Add this development-only route:

        if Application.compile_env(:#{binding[:app_module] |> Macro.underscore()}, :dev_routes, false) do
          scope "/dev", #{binding[:web_module]} do
            pipe_through :browser
            post "/account-switcher", AnyLoginController, :switch
          end
        end

    Add the component to your root layout:

        <%= if @any_login_enabled do %>
          <#{binding[:web_module]}.AnyLoginComponent.account_switcher
            users={@any_login_users}
            current_user={@current_scope && @current_scope.user}
            return_to={@any_login_return_to}
          />
        <% end %>
    """)
  end
end
