#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid, {:diode_client, "~> 1.4.9"}])
Code.eval_file("scripts/factory.ex")
:erlang.system_flag(:backtrace_depth, 30)

w = Factory.wallet()

case System.argv() do
  [env, destination_text] ->
    factory =
      case env do
        "local" ->
          System.put_env("ICP_DOMAIN", "http://127.0.0.1:4943")
          {id, 0} = System.cmd("dfx", ["canister", "id", "CanisterFactory"])
          String.trim(id)

        "ic" ->
          Factory.id()
      end

    destination = ICPAgent.decode_textual(destination_text)
    {_, 0} = System.cmd("dfx", ["build", "--check", "ZoneAvailabilityCanister"])

    wasm =
      File.read!("./.dfx/local/canisters/ZoneAvailabilityCanister/ZoneAvailabilityCanister.wasm")

    [zone_id] = ICPAgent.query(destination_text, w, "get_zone_id")
    IO.puts("ZoneID: #{zone_id}")
    DiodeClient.interface_add()

    chain = Factory.detect_chain(zone_id)
    if chain == nil, do: raise("Zone not found on-chain")

    IO.puts("Chain: #{chain}")
    [version] = ICPAgent.query(destination_text, w, "get_version")
    IO.puts("Current canister version: #{version}")

    {rpc_host, rpc_path} = Factory.rpc_for_chain(chain)

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
      cycles_requester_id: ICPAgent.decode_textual(factory),
      call_token: nil
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
    [new_zone_id] = ICPAgent.query(destination_text, w, "get_zone_id")
    backend = Factory.get_rpc_backend(destination_text)
    IO.puts("New canister version: #{new_version}")
    IO.puts("Zone ID after upgrade: #{new_zone_id}")
    IO.puts("RPC backend: #{inspect(backend)}")
    IO.puts("Done! Review at: #{url}#{destination_text}")

  _ ->
    IO.puts("Usage: upgrade_canister.exs (local|ic) <canister_id>")
end
