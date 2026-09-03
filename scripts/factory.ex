defmodule Factory do
  def id() do
    "dgnum-qiaaa-aaaao-qj3ta-cai"
  end

  def target_zac_version(), do: 415

  def wallet() do
    File.read!("diode_glmr.key")
    |> String.trim()
    |> DiodeClient.Base16.decode()
    |> DiodeClient.Wallet.from_privkey()
  end

  # Queries (children list, get_version, etc.) do not need the admin key.
  def query_wallet() do
    DiodeClient.Wallet.new()
  end

  def children() do
    ICPAgent.query(id(), query_wallet(), "get_cycles_manager_children", [], [], {:vec, :principal})
    |> Enum.map(&ICPAgent.encode_textual/1)
  end

  def refill(canister_id) do
    canister_id = ICPAgent.decode_textual(canister_id)

    result_type =
      {:variant,
       [
         ok: :nat,
         err:
           {:variant,
            [
              insufficient_cycles_available: :null,
              too_few_cycles_requested: :null,
              aggregate_quota_reached: :null,
              canister_quota_reached: :null,
              other: :text
            ]}
       ]}

    ICPAgent.call(
      id(),
      DiodeClient.Wallet.new(),
      "cycles_manager_transferCyclesToCanister",
      [:principal],
      [canister_id],
      result_type
    )
  end

  def start_canister(canister_id) do
    canister_id = ICPAgent.decode_textual(canister_id)
    ICPAgent.call(id(), wallet(), "start_canister", [:principal], [canister_id])
  end

  def rpc_for_chain(chain) do
    case chain do
      "moonbeam" -> {"rpc.api.moonbeam.network", "/"}
      "diode" -> {"prenet.diode.io:8443", "/"}
      "oasis" -> {"sapphire.oasis.io", "/"}
      "base" -> {"mainnet.base.org", "/"}
    end
  end

  def detect_chain(zone_id) when is_binary(zone_id) do
    account = DiodeClient.Base16.decode(zone_id)

    cond do
      DiodeClient.Shell.Base.get_account_root(account) != nil -> "base"
      DiodeClient.Shell.Moonbeam.get_account_root(account) != nil -> "moonbeam"
      DiodeClient.Shell.get_account_root(account) != nil -> "diode"
      DiodeClient.Shell.OasisSapphire.get_account_root(account) != nil -> "oasis"
      true -> nil
    end
  end

  def upgrade(canister_id, chain, zone_id, wasm) do
    canister_id = ICPAgent.decode_textual(canister_id)
    {rpc_host, rpc_path} = rpc_for_chain(chain)

    type = %{
      zone_id: :text,
      rpc_host: :text,
      rpc_path: :text,
      cycles_requester_id: :principal,
      call_token: {:opt, :blob}
    }

    values = %{
      zone_id: zone_id,
      rpc_host: rpc_host,
      rpc_path: rpc_path,
      cycles_requester_id: ICPAgent.decode_textual(id()),
      call_token: nil
    }

    args = Candid.encode_parameters([{:record, type}], [values])

    ICPAgent.call(id(), wallet(), "upgrade_code", [:principal, :blob, :blob], [
      canister_id,
      wasm,
      args
    ])
  end

  def get_rpc_backend(canister_id) do
    backend_type =
      {:variant,
       [
         HttpOutcall: %{host: :text, path: :text},
         ChainFusion: %{network: {:variant, [BaseMainnet: :null]}}
       ]}

    ICPAgent.query(canister_id, query_wallet(), "get_rpc_backend", [], [], backend_type)
  end

  def update_aggregate_quota_settings(max_amount, duration_in_seconds \\ nil) do
    duration_in_seconds = duration_in_seconds || 24 * 60 * 60

    ICPAgent.call(id(), wallet(), "update_aggregate_quota_settings", [:nat, :nat], [
      max_amount,
      duration_in_seconds
    ])
  end
end
