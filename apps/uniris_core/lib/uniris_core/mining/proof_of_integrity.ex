defmodule UnirisCore.Mining.ProofOfIntegrity do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Crypto

  @doc """
  Produce a proof of integrity for a given chain.

  If the chain contains only a transaction the hash of the pending is transaction is returned
  Otherwise the hash of the pending transaction and the previous proof of integrity are hashed together
  """
  @spec compute(chain :: [Transaction.pending() | list(Transaction.validated())]) :: binary()
  def compute([tx = %Transaction{} | []]) do
    from_transaction(tx)
  end

  def compute([
        tx = %Transaction{}
        | [
            %Transaction{
              validation_stamp: %ValidationStamp{proof_of_integrity: previous_poi}
            }
            | _
          ]
      ]) do
    Crypto.hash([from_transaction(tx), previous_poi])
  end

  defp from_transaction(tx = %Transaction{}) do
    tx
    |> Transaction.to_pending()
    |> Crypto.hash()
  end

  @doc """
  Verifies the proof of integrity from a given chain of transaction by recompute it
  from the previous chain retrieved from the context building and asserts its equality
  """
  @spec verify?(proof_of_integrity :: binary(), chain :: list(Transaction.validated())) ::
          boolean()
  def verify?("", _chain), do: false

  def verify?(poi, chain) when is_list(chain) and is_binary(poi) do
    compute(chain) == poi
  end
end
