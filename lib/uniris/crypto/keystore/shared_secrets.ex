defmodule Uniris.Crypto.SharedSecretsKeystore do
  @moduledoc false

  alias __MODULE__.SoftwareImpl
  alias Uniris.Crypto.SharedSecretsKeystoreImpl

  # TODO: detect the implementation to use (software, SGX)
  @default_impl SoftwareImpl

  @behaviour SharedSecretsKeystoreImpl

  def child_spec(opts), do: impl().child_spec(opts)

  @impl SharedSecretsKeystoreImpl
  def sign_with_node_shared_secrets_key(data), do: impl().sign_with_node_shared_secrets_key(data)

  @impl SharedSecretsKeystoreImpl
  def sign_with_node_shared_secrets_key(data, index),
    do: impl().sign_with_node_shared_secrets_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def sign_with_network_pool_key(data), do: impl().sign_with_network_pool_key(data)

  @impl SharedSecretsKeystoreImpl
  def sign_with_network_pool_key(data, index), do: impl().sign_with_network_pool_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def sign_with_daily_nonce_key(data, index), do: impl().sign_with_daily_nonce_key(data, index)

  @impl SharedSecretsKeystoreImpl
  def node_shared_secrets_public_key(index), do: impl().node_shared_secrets_public_key(index)

  @impl SharedSecretsKeystoreImpl
  def network_pool_public_key(index), do: impl().network_pool_public_key(index)

  @impl SharedSecretsKeystoreImpl
  def wrap_secrets(secret_key),
    do: impl().wrap_secrets(secret_key)

  @impl SharedSecretsKeystoreImpl
  def unwrap_secrets(encrypted_secrets, encrypted_key, timestamp),
    do: impl().unwrap_secrets(encrypted_secrets, encrypted_key, timestamp)

  defp impl do
    Application.get_env(:uniris, __MODULE__, impl: @default_impl)
    |> Keyword.fetch!(:impl)
  end
end
