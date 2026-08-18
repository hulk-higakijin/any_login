defmodule AnyLogin.Component do
  @moduledoc "The development account switcher component."

  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  attr(:users, :list, required: true)
  attr(:current_user, :map, default: nil)
  attr(:return_to, :string, default: "/")
  attr(:switch_path, :string, default: "/dev/account-switcher")
  attr(:logout_path, :string, default: "/users/log-out")

  def account_switcher(assigns) do
    ~H"""
    <section id="any-login-switcher" class="fixed bottom-4 left-4 z-50">
      <details class="relative">
        <summary
          id="any-login-switcher-toggle"
          aria-label="Open development account switcher"
          class="flex size-10 cursor-pointer list-none items-center justify-center rounded-lg bg-orange-400 text-white shadow-lg transition hover:bg-orange-500 focus:outline-none focus:ring-2 focus:ring-orange-300"
        >
          <span aria-hidden="true" class="text-lg">&#x1F464;</span>
        </summary>

        <div id="any-login-switcher-panel" class="absolute bottom-12 left-0 w-80 rounded-xl border bg-base-100 p-4 shadow-xl">
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
            <div class="mt-3 flex items-center justify-between border-t pt-3 text-sm">
              <span>{Map.get(@current_user, :email, @current_user.id)}</span>
              <form action={@logout_path} method="post" id="any-login-logout-form">
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                <button type="submit" class="underline">Log out</button>
              </form>
            </div>
          <% end %>
        </div>
      </details>
    </section>
    """
  end
end
