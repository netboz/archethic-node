defmodule ArchethicWeb.LayoutView do
  @moduledoc false
  use ArchethicWeb, :view

  def faucet?() do
    Application.get_env(:archethic, ArchethicWeb.FaucetController)
    |> Keyword.get(:enabled, false)
  end
end
