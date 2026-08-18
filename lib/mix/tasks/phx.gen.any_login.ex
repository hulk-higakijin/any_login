defmodule Mix.Tasks.Phx.Gen.AnyLogin do
  @shortdoc "Generates a development-only account switcher"

  @moduledoc """
  Generates a development-only account switcher for a Phoenix application.

      mix phx.gen.any_login Accounts users

  The first argument is the existing context module and the second argument is
  the users table name. The generator creates the account switcher modules and
  automatically updates the context, browser pipeline, development routes, and
  root layout. The application's `UserAuth` module must expose `log_in_user/2`.

  Pass `--no-inject` to generate only the three AnyLogin modules. If the schema
  cannot be detected from its Ecto table name, pass its full module name with
  `--schema MyApp.Accounts.User`.
  """
  use Mix.Task

  alias Mix.Generator

  @switches [
    app: :string,
    auth: :string,
    force: :boolean,
    no_inject: :boolean,
    path: :string,
    schema: :string,
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

    changes =
      if opts[:no_inject] do
        []
      else
        integration_changes!(binding, root, opts)
      end

    files = generated_files(binding, root)

    Enum.each(files, fn {path, contents} ->
      Generator.create_file(path, contents, force: opts[:force] == true)
    end)

    apply_changes(changes)
    print_result(binding, opts[:no_inject] == true)
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

  defp integration_changes!(binding, root, opts) do
    router_path = project_path(root, binding[:web_module], "router.ex")
    layout_path = project_path(root, binding[:web_module], "components/layouts/root.html.heex")
    context_path = Path.join(root, "lib/#{Macro.underscore(binding[:context_module])}.ex")

    schema_module =
      case opts[:schema] do
        nil -> find_schema_module!(binding[:context_module], binding[:table], root)
        schema -> validate_context!(schema)
      end

    [
      change_file!(router_path, &integrate_router(&1, binding)),
      change_file!(layout_path, &integrate_layout(&1, binding)),
      change_file!(context_path, &integrate_context(&1, binding, schema_module))
    ]
  end

  defp project_path(root, web_module, relative_path) do
    Path.join(root, "lib/#{Macro.underscore(web_module)}/#{relative_path}")
  end

  defp change_file!(path, transform) do
    source =
      case File.read(path) do
        {:ok, source} -> source
        {:error, reason} -> Mix.raise("Could not read #{path}: #{:file.format_error(reason)}")
      end

    {path, source, transform.(source)}
  end

  defp find_schema_module!(context_module, table, root) do
    context_dir = Path.join(root, "lib/#{Macro.underscore(context_module)}")

    schema_pattern =
      ~r/defmodule\s+([A-Z][A-Za-z0-9_.]*)\s+do[\s\S]*?\bschema\s+#{inspect(table)}/

    context_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.find_value(fn path ->
      case Regex.run(schema_pattern, File.read!(path), capture: :all_but_first) do
        [module] -> module
        nil -> nil
      end
    end)
    |> case do
      nil ->
        Mix.raise("""
        Could not find an Ecto schema for table #{inspect(table)} under #{context_dir}.
        Pass it explicitly, for example: --schema #{context_module}.User
        """)

      module ->
        module
    end
  end

  defp integrate_router(source, binding) do
    source
    |> inject_browser_plug(binding[:web_module])
    |> inject_development_route(binding)
  end

  defp inject_browser_plug(source, web_module) do
    plug = "plug #{web_module}.AnyLogin"

    if String.contains?(source, plug) do
      source
    else
      inject_before_block_end!(
        source,
        ~r/^(\s*)pipeline\s+:browser\s+do\s*$/,
        fn indent -> "#{indent}  #{plug}\n" end,
        "the :browser pipeline"
      )
    end
  end

  defp inject_development_route(source, binding) do
    route_pattern =
      ~r/^\s*post\s+"\/account-switcher",\s+(?:[A-Z][A-Za-z0-9_.]*\.)?AnyLoginController,\s+:switch\s*$/m

    if Regex.match?(route_pattern, source) do
      source
    else
      do_inject_development_route(source, binding)
    end
  end

  defp do_inject_development_route(source, binding) do
    app = binding[:app_module] |> Macro.underscore()

    dev_pattern =
      ~r/^(\s*)if\s+Application\.compile_env\(\s*:#{Regex.escape(app)},\s*:dev_routes(?:,\s*false)?\s*\)\s+do\s*$/

    scope = fn indent ->
      """
      #{indent}  scope "/dev", #{binding[:web_module]} do
      #{indent}    pipe_through :browser

      #{indent}    post "/account-switcher", AnyLoginController, :switch
      #{indent}  end

      """
    end

    case find_line(source, dev_pattern) do
      {:ok, index, indent, lines} ->
        List.insert_at(lines, index + 1, scope.(indent)) |> Enum.join()

      :error ->
        block =
          """

            if Application.compile_env(:#{app}, :dev_routes, false) do
              scope "/dev", #{binding[:web_module]} do
                pipe_through :browser

                post "/account-switcher", AnyLoginController, :switch
              end
            end
          """

        inject_before_final_end!(source, block, "the router module")
    end
  end

  defp integrate_layout(source, binding) do
    if String.contains?(source, "AnyLoginComponent.account_switcher") do
      source
    else
      component =
        """
            <%= if assigns[:any_login_enabled] do %>
              <#{binding[:web_module]}.AnyLoginComponent.account_switcher
                users={@any_login_users}
                current_user={assigns[:current_scope] && assigns[:current_scope].user}
                return_to={@any_login_return_to}
              />
            <% end %>
        """

      case String.split(source, "</body>", parts: 2) do
        [before, after_body] -> before <> component <> "  </body>" <> after_body
        [_] -> Mix.raise("Could not find </body> in the root layout")
      end
    end
  end

  defp integrate_context(source, binding, schema_module) do
    functions =
      [
        unless(function_defined?(source, "list_users"),
          do: "  def list_users, do: #{binding[:app_module]}.Repo.all(#{schema_module})\n"
        ),
        unless(function_defined?(source, "get_user"),
          do: "  def get_user(id), do: #{binding[:app_module]}.Repo.get(#{schema_module}, id)\n"
        )
      ]
      |> Enum.reject(&is_nil/1)

    case functions do
      [] ->
        source

      functions ->
        inject_before_final_end!(source, "\n" <> Enum.join(functions, "\n"), "the context module")
    end
  end

  defp function_defined?(source, name) do
    Regex.match?(~r/^\s*def\s+#{name}(?:\s*\(|\s+[^!]|,)/m, source)
  end

  defp inject_before_block_end!(source, header_pattern, snippet, description) do
    case find_line(source, header_pattern) do
      {:ok, index, indent, lines} ->
        end_index =
          lines
          |> Enum.with_index()
          |> Enum.drop(index + 1)
          |> Enum.find_value(fn {line, line_index} ->
            if String.trim_trailing(line) == "#{indent}end", do: line_index
          end)

        if end_index do
          List.insert_at(lines, end_index, snippet.(indent)) |> Enum.join()
        else
          Mix.raise("Could not find the end of #{description}")
        end

      :error ->
        Mix.raise("Could not find #{description}")
    end
  end

  defp find_line(source, pattern) do
    lines = String.split(source, ~r/(?<=\n)/)

    case Enum.find_index(lines, &Regex.match?(pattern, String.trim_trailing(&1))) do
      nil ->
        :error

      index ->
        [indent] =
          Regex.run(pattern, String.trim_trailing(Enum.at(lines, index)), capture: :all_but_first)

        {:ok, index, indent, lines}
    end
  end

  defp inject_before_final_end!(source, snippet, description) do
    trimmed = String.trim_trailing(source)

    if String.ends_with?(trimmed, "end") do
      String.replace_suffix(trimmed, "end", snippet <> "end\n")
    else
      Mix.raise("Could not find the end of #{description}")
    end
  end

  defp apply_changes(changes) do
    Enum.each(changes, fn
      {_path, source, source} ->
        :ok

      {path, _source, updated} ->
        Mix.shell().info([:green, "* injecting ", :reset, Path.relative_to_cwd(path)])
        File.write!(path, updated)
    end)
  end

  defp controller_template(binding) do
    """
    defmodule #{binding[:web_module]}.AnyLoginController do
      use #{binding[:web_module]}, :controller

      alias #{binding[:context_module]}
      alias #{binding[:auth_module]}

      def switch(conn, %{"user_id" => user_id} = params) do
        with {id, ""} <- Integer.parse(user_id),
             user when not is_nil(user) <- Accounts.get_user(id) do
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
          |> assign(:any_login_users, Accounts.list_users())
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
        <section id="any-login-switcher" class="fixed bottom-4 left-4 z-50">
          <button
            type="button"
            id="any-login-switcher-toggle"
            data-any-login-switcher-toggle
            aria-label="Open development account switcher"
            aria-controls="any-login-switcher-panel"
            aria-expanded="false"
            class="flex size-10 items-center justify-center rounded-lg bg-orange-400 text-white shadow-lg transition hover:bg-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-300"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true" class="size-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6.75a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.5 20.118a7.5 7.5 0 0 1 15 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.5-1.632Z" />
            </svg>
          </button>

          <div
            id="any-login-switcher-panel"
            data-any-login-switcher-panel
            hidden
            class="absolute bottom-12 left-0 hidden w-80 rounded-xl border bg-base-100 p-4 shadow-xl"
          >
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
          </div>
        </section>

        <script>
          (() => {
            const switcher = document.getElementById("any-login-switcher");
            if (!switcher || switcher.dataset.initialized) return;

            switcher.dataset.initialized = "true";
            const toggle = switcher.querySelector("[data-any-login-switcher-toggle]");
            const panel = switcher.querySelector("[data-any-login-switcher-panel]");

            const close = () => {
              panel.hidden = true;
              panel.classList.add("hidden");
              toggle.setAttribute("aria-expanded", "false");
            };

            toggle.addEventListener("click", () => {
              const opening = panel.hidden;
              panel.hidden = !opening;
              panel.classList.toggle("hidden", !opening);
              toggle.setAttribute("aria-expanded", String(opening));
            });

            document.addEventListener("click", (event) => {
              if (!switcher.contains(event.target)) close();
            });
          })();
        </script>
        \"\"\"
      end
    end
    """
    |> Code.format_string!()
  end

  defp print_result(binding, false) do
    Mix.shell().info("""

    AnyLogin installed for #{binding[:context_module]}.#{binding[:table]}.
    Router, root layout, and context integration are ready. No manual setup is required.
    """)
  end

  defp print_result(binding, true) do
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

        <%= if assigns[:any_login_enabled] do %>
          <#{binding[:web_module]}.AnyLoginComponent.account_switcher
            users={@any_login_users}
            current_user={assigns[:current_scope] && assigns[:current_scope].user}
            return_to={@any_login_return_to}
          />
        <% end %>
    """)
  end
end
