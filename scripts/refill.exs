#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid])

case System.argv() do
  [canister_id] ->
    canister_id = ICPAgent.decode_textual(canister_id)
    factory = "dgnum-qiaaa-aaaao-qj3ta-cai"

    IO.inspect(
      ICPAgent.call(
        factory,
        DiodeClient.Wallet.new(),
        "cycles_manager_transferCyclesToCanister",
        [:principal],
        [canister_id]
      )
    )

  _ ->
    IO.puts("Usage: elixir refill.exs <canister_id>")
end
