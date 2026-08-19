defmodule Mix.Tasks.Phx.Gen.AnyLogin do
  @shortdoc "Integrates a development-only account switcher"

  @moduledoc """
  Integrates AnyLogin into a Phoenix application.

      mix phx.gen.any_login Accounts users

  The application must provide a `UserAuth` module exposing `log_in_user/2`.
  The task discovers the user schema from the table name and updates only the
  development config, browser pipeline, development route, and root layout.
  """

  use Mix.Task

  @switches [
    app: :string,
    auth: :string,
    no_inject: :boolean,
    path: :string,
    schema: :string,
    web: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    {context, table} = parse_arguments!(positional)
    app_module = Macro.camelize(opts[:app] || Mix.Project.config()[:app] |> to_string())
    web_module = opts[:web] || "#{app_module}Web"
    auth_module = opts[:auth] || "#{web_module}.UserAuth"
    root = opts[:path] || File.cwd!()
    context_module = qualify_context(context, app_module)
    schema_module = opts[:schema] || find_schema_module!(context_module, table, root)

    binding = [
      app_module: app_module,
      auth_module: auth_module,
      context_module: context_module,
      schema_module: schema_module,
      table: table,
      web_module: web_module
    ]

    changes = if opts[:no_inject], do: [], else: integration_changes!(binding, root)
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
        Mix.raise(
          "Could not find an Ecto schema for table #{inspect(table)} under #{context_dir}"
        )

      module ->
        module
    end
  end

  defp integration_changes!(binding, root) do
    router_path = project_path(root, binding[:web_module], "router.ex")
    layout_path = project_path(root, binding[:web_module], "components/layouts/root.html.heex")
    config_path = Path.join(root, "config/dev.exs")

    [
      change_file!(router_path, &integrate_router(&1, binding)),
      change_file!(layout_path, &integrate_layout/1),
      change_file!(config_path, &integrate_config(&1, binding))
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

  defp integrate_router(source, binding) do
    source
    |> inject_browser_plug(binding)
    |> inject_development_route(binding)
  end

  defp inject_browser_plug(source, binding) do
    app = Macro.underscore(binding[:app_module])
    plug = "plug AnyLogin.Plug, enabled: Application.compile_env(:#{app}, :dev_routes, false)"

    if String.contains?(source, "plug AnyLogin.Plug") do
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
      ~r/^\s*post\s+"\/account-switcher",\s+(?:Elixir\.)?AnyLogin\.Controller,\s+:switch\s*$/m

    if Regex.match?(route_pattern, source) do
      source
    else
      app = Macro.underscore(binding[:app_module])

      dev_pattern =
        ~r/^(\s*)if\s+Application\.compile_env\(\s*:#{Regex.escape(app)},\s*:dev_routes(?:,\s*false)?\s*\)\s+do\s*$/

      scope = fn indent ->
        """
        #{indent}  scope "/dev", #{binding[:web_module]} do
        #{indent}    pipe_through :browser

        #{indent}    post "/account-switcher", Elixir.AnyLogin.Controller, :switch
        #{indent}  end

        """
      end

      case find_line(source, dev_pattern) do
        {:ok, index, indent, lines} ->
          List.insert_at(lines, index + 1, scope.(indent)) |> Enum.join()

        :error ->
          block = """

            if Application.compile_env(:#{app}, :dev_routes, false) do
              scope "/dev", #{binding[:web_module]} do
                pipe_through :browser

                post "/account-switcher", Elixir.AnyLogin.Controller, :switch
              end
            end
          """

          inject_before_final_end!(source, block, "the router module")
      end
    end
  end

  defp integrate_layout(source) do
    if String.contains?(source, "AnyLogin.Component.account_switcher") do
      source
    else
      component = """
          <%= if assigns[:any_login_enabled] do %>
            <AnyLogin.Component.account_switcher
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

  defp integrate_config(source, binding) do
    if String.contains?(source, "config :any_login") do
      source
    else
      config = """

      config :any_login,
        repo: #{binding[:app_module]}.Repo,
        schema: #{binding[:schema_module]},
        auth: #{binding[:auth_module]}
      """

      String.trim_trailing(source) <> config
    end
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

  defp print_result(binding, false) do
    Mix.shell().info("AnyLogin installed for #{binding[:context_module]}.#{binding[:table]}.")
  end

  defp print_result(binding, true) do
    Mix.shell().info("""

    AnyLogin runtime integration for #{binding[:context_module]}.#{binding[:table]}:

    config :any_login,
      repo: #{binding[:app_module]}.Repo,
      schema: #{binding[:schema_module]},
      auth: #{binding[:auth_module]}

    plug AnyLogin.Plug,
      enabled: Application.compile_env(:#{Macro.underscore(binding[:app_module])}, :dev_routes, false)

    post "/account-switcher", Elixir.AnyLogin.Controller, :switch

    <AnyLogin.Component.account_switcher
      users={@any_login_users}
      current_user={assigns[:current_scope] && assigns[:current_scope].user}
      return_to={@any_login_return_to}
    />
    """)
  end
end
