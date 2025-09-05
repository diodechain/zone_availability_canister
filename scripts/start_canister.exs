#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid])

case System.argv() do
  [canister_id] ->
    canister_id = ICPAgent.decode_textual(canister_id)
    factory = "dgnum-qiaaa-aaaao-qj3ta-cai"

    w =
      File.read!("diode_glmr.key")
      |> String.trim()
      |> DiodeClient.Base16.decode()
      |> DiodeClient.Wallet.from_privkey()

    IO.inspect(ICPAgent.call(factory, w, "start_canister", [:principal], [canister_id]))

  _ ->
    IO.puts("Usage: elixir start_canister.exs <canister_id>")
end
