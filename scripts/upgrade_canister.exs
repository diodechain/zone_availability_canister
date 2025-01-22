#!/usr/bin/env elixir
Mix.install([:icp_agent, {:candid, "~> 1.1.0", override: true}])
:erlang.system_flag(:backtrace_depth, 30)

w =
  File.read!("diode_glmr.key")
  |> String.trim()
  |> DiodeClient.Base16.decode()
  |> DiodeClient.Wallet.from_privkey()

factory = "dgnum-qiaaa-aaaao-qj3ta-cai"

case System.argv() do
  [destination_text, chain] ->
    destination = ICPAgent.decode_textual(destination_text)
    {_, 0} = System.cmd("dfx", ["build", "ZoneAvailabilityCanister"])

    wasm =
      File.read!("./.dfx/local/canisters/ZoneAvailabilityCanister/ZoneAvailabilityCanister.wasm")

    [zone_id] = ICPAgent.query(destination_text, w, "get_zone_id")

    {rpc_host, rpc_path} =
      case chain do
        "moonbeam" ->
          {"rpc.api.moonbeam.network", "/"}

        "diode" ->
          {"prenet.diode.io:8443", "/"}
      end

    type = %{zone_id: :text, rpc_host: :text, rpc_path: :text, cycles_requester_id: :principal}
    values = %{
      zone_id: zone_id,
      rpc_host: rpc_host,
      rpc_path: rpc_path,
      cycles_requester_id: ICPAgent.decode_textual(factory)
    }

    args = Candid.encode_parameters([{:record, type}], [values])

    [] = ICPAgent.call(factory, w, "install_code", [:principal, :blob, :blob], [
      destination,
      wasm,
      args
    ])

    IO.puts("Done! Review at: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id=#{destination_text}")

  _ ->
    IO.puts("Usage: upgrade_canister.exs <destination> (moonbeam|diode)")
end
