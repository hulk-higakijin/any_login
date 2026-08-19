defmodule AnyLogin.Component do
  @moduledoc "The development account switcher component."

  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  @css_path Path.expand("../../assets/any_login.css", __DIR__)
  @external_resource @css_path
  @css File.read!(@css_path)

  attr(:users, :list, required: true)
  attr(:current_user, :map, default: nil)
  attr(:return_to, :string, default: "/")
  attr(:switch_path, :string, default: "/dev/account-switcher")
  attr(:logout_path, :string, default: "/users/log-out")

  def account_switcher(assigns) do
    assigns = Map.put(assigns, :any_login_css, @css)

    ~H"""
    <style id="any-login-styles"><%= @any_login_css %></style>
    <section id="any-login-switcher" class="any-login-switcher">
      <details class="any-login-switcher__details">
        <summary
          id="any-login-switcher-toggle"
          aria-label="Open development account switcher"
          class="any-login-switcher__toggle"
        >
          <span aria-hidden="true" class="text-lg">&#x1F464;</span>
        </summary>

        <div id="any-login-switcher-panel" class="any-login-switcher__panel">
          <p class="any-login-switcher__title">Development account</p>
          <form action={@switch_path} method="post" id="any-login-switcher-form" class="any-login-switcher__form">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="return_to" value={@return_to} />
            <label for="any-login-user-id" class="sr-only">Account</label>
            <select id="any-login-user-id" name="user_id" required class="any-login-switcher__select">
              <option value="">Select an account</option>
              <%= for user <- @users do %>
                <option value={user.id} selected={@current_user && @current_user.id == user.id}>
                  {Map.get(user, :email, user.id)}
                </option>
              <% end %>
            </select>
            <button type="submit" class="any-login-switcher__button">
              Switch account
            </button>
          </form>
          <%= if @current_user do %>
            <div class="any-login-switcher__current">
              <span>{Map.get(@current_user, :email, @current_user.id)}</span>
              <form action={@logout_path} method="post" id="any-login-logout-form">
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                <button type="submit" class="any-login-switcher__logout">Log out</button>
              </form>
            </div>
          <% end %>
        </div>
      </details>
    </section>
    """
  end
end
