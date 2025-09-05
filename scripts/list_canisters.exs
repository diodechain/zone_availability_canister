#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid])
:erlang.system_flag(:backtrace_depth, 30)

w =
  File.read!("diode_glmr.key")
  |> String.trim()
  |> DiodeClient.Base16.decode()
  |> DiodeClient.Wallet.from_privkey()

factory = "dgnum-qiaaa-aaaao-qj3ta-cai"

[children] =
  ICPAgent.query(factory, w, "get_cycles_manager_children", [], [], [{:vec, :principal}])

children = Enum.map(children, &ICPAgent.encode_textual/1) |> Enum.with_index()

{upgrade?, wasm} =
  if "--upgrade" in System.argv() do
    DiodeClient.interface_add()
    {_, 0} = System.cmd("dfx", ["build", "--check", "ZoneAvailabilityCanister"])

    wasm =
      File.read!("./.dfx/local/canisters/ZoneAvailabilityCanister/ZoneAvailabilityCanister.wasm")

    {true, wasm}
  else
    {false, nil}
  end

for {child, index} <- children do
  IO.puts("#{index} - #{child}")

  if upgrade? do
    [version] = ICPAgent.query(child, w, "get_version")
    IO.puts("Current canister version: #{version}")

    if version < 410 do
      [zone_id] = ICPAgent.query(child, w, "get_zone_id")
      account = DiodeClient.Base16.decode(zone_id)

      chain =
        cond do
          DiodeClient.Shell.Moonbeam.get_account_root(account) != nil -> "moonbeam"
          DiodeClient.Shell.get_account_root(account) != nil -> "diode"
          true -> raise "Zone not found on-chain"
        end

      {rpc_host, rpc_path} =
        case chain do
          "moonbeam" ->
            {"rpc.api.moonbeam.network", "/"}

          "diode" ->
            {"prenet.diode.io:8443", "/"}
        end

      IO.puts("ZoneID: #{zone_id} @ #{chain}")

      type = %{zone_id: :text, rpc_host: :text, rpc_path: :text, cycles_requester_id: :principal}

      values = %{
        zone_id: zone_id,
        rpc_host: rpc_host,
        rpc_path: rpc_path,
        cycles_requester_id: ICPAgent.decode_textual(factory)
      }

      args = Candid.encode_parameters([{:record, type}], [values])

      [] =
        ICPAgent.call(factory, w, "upgrade_code", [:principal, :blob, :blob], [
          ICPAgent.decode_textual(child),
          wasm,
          args
        ])
    end
  end
end
