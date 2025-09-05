#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid])
:erlang.system_flag(:backtrace_depth, 30)

w =
  File.read!("diode_glmr.key")
  |> String.trim()
  |> DiodeClient.Base16.decode()
  |> DiodeClient.Wallet.from_privkey()

case System.argv() do
  [env, destination_text] ->
    factory =
      case env do
        "local" ->
          System.put_env("ICP_DOMAIN", "http://127.0.0.1:4943")
          {id, 0} = System.cmd("dfx", ["canister", "id", "CanisterFactory"])
          String.trim(id)

        "ic" ->
          "dgnum-qiaaa-aaaao-qj3ta-cai"
      end

    destination = ICPAgent.decode_textual(destination_text)
    {_, 0} = System.cmd("dfx", ["build", "--check", "ZoneAvailabilityCanister"])

    wasm =
      File.read!("./.dfx/local/canisters/ZoneAvailabilityCanister/ZoneAvailabilityCanister.wasm")

    [zone_id] = ICPAgent.query(destination_text, w, "get_zone_id")
    IO.puts("ZoneID: #{zone_id}")
    account = DiodeClient.Base16.decode(zone_id)
    DiodeClient.interface_add()

    chain =
      cond do
        DiodeClient.Shell.Moonbeam.get_account_root(account) != nil -> "moonbeam"
        DiodeClient.Shell.get_account_root(account) != nil -> "diode"
        true -> raise "Zone not found on-chain"
      end

    IO.puts("Chain: #{chain}")
    [version] = ICPAgent.query(destination_text, w, "get_version")
    IO.puts("Current canister version: #{version}")

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

    [] =
      ICPAgent.call(factory, w, "upgrade_code", [:principal, :blob, :blob], [
        destination,
        wasm,
        args
      ])

    url =
      if env == "local" do
        "http://127.0.0.1:4943/?canisterId=u6s2n-gx777-77774-qaaba-cai&id="
      else
        "https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id="
      end

    [new_version] = ICPAgent.query(destination_text, w, "get_version")
    IO.puts("New canister version: #{new_version}")
    IO.puts("Done! Review at: #{url}#{destination_text}")

  _ ->
    IO.puts("Usage: upgrade_canister.exs (local|ic) <destination>")
end
