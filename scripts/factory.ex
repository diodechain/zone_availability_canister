defmodule Factory do
  def id() do
    "dgnum-qiaaa-aaaao-qj3ta-cai"
  end

  def wallet() do
    File.read!("diode_glmr.key")
    |> String.trim()
    |> DiodeClient.Base16.decode()
    |> DiodeClient.Wallet.from_privkey()
  end

  def children() do
    ICPAgent.query(id(), wallet(), "get_cycles_manager_children", [], [], {:vec, :principal})
    |> Enum.map(&ICPAgent.encode_textual/1)
  end

  def refill(canister_id) do
    canister_id = ICPAgent.decode_textual(canister_id)
    # public type TransferCyclesResult = Result.Result<Nat, TransferCyclesError>;
    # public type TransferCyclesError = {
    #   // The sending canister does not have enough cycles to send.
    #   #insufficient_cycles_available;
    #   // The requesting canister has asked for too few cycles.
    #   #too_few_cycles_requested;
    #   // The cycles manager has reached its aggregate quota.
    #   #aggregate_quota_reached;
    #   // The canister has reached its quota.
    #   #canister_quota_reached;
    #   // Some other error.
    #   #other : Text;
    # };
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

  def upgrade(canister_id, chain, zone_id, wasm) do
    canister_id = ICPAgent.decode_textual(canister_id)

    {rpc_host, rpc_path} =
      case chain do
        "moonbeam" -> {"rpc.api.moonbeam.network", "/"}
        "diode" -> {"prenet.diode.io:8443", "/"}
        "oasis" -> {"sapphire.oasis.io", "/"}
      end

    type = %{
      zone_id: :text,
      rpc_host: :text,
      rpc_path: :text,
      cycles_requester_id: :principal
    }

    values = %{
      zone_id: zone_id,
      rpc_host: rpc_host,
      rpc_path: rpc_path,
      cycles_requester_id: ICPAgent.decode_textual(id())
    }

    args = Candid.encode_parameters([{:record, type}], [values])

    ICPAgent.call(id(), wallet(), "upgrade_code", [:principal, :blob, :blob], [
      canister_id,
      wasm,
      args
    ])
  end

  def update_aggregate_quota_settings(max_amount, duration_in_seconds \\ nil) do
    duration_in_seconds = duration_in_seconds || 24 * 60 * 60

    ICPAgent.call(id(), wallet(), "update_aggregate_quota_settings", [:nat, :nat], [
      max_amount,
      duration_in_seconds
    ])
  end
end
