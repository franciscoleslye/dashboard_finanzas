import Config

db_username = System.get_env("DB_USERNAME") || System.get_env("USER") || "postgres"
db_password = System.get_env("DB_PASSWORD") || ""
db_hostname = System.get_env("DB_HOST") || "localhost"
db_port = String.to_integer(System.get_env("DB_PORT") || "5432")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dashboard_finanzas, DashboardFinanzas.Repo,
  username: db_username,
  password: db_password,
  hostname: db_hostname,
  port: db_port,
  database: "dashboard_finanzas_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dashboard_finanzas, DashboardFinanzasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "N3efd3vYgHs6WlGNhgqlu210zZ/GyAVXZhTVh3WkC+fh1e3Am/9TMC1GPxL69Nt7",
  server: false

# In test we don't send emails
config :dashboard_finanzas, DashboardFinanzas.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
