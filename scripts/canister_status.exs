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

    return_type = %{
      status: [:stopped, :stopping, :running],
      memory_size: :nat,
      cycles: :nat,
      settings: %{
        freezing_threshold: :nat,
        controllers: {:vec, :principal},
        reserved_cycles_limit: :nat,
        log_visibility: {:opt, [:controllers, :public_]},
        wasm_memory_limit: :nat,
        memory_allocation: :nat,
        compute_allocation: :nat
      },
      query_stats: %{
        response_payload_bytes_total: :nat,
        num_instructions_total: :nat,
        num_calls_total: :nat,
        request_payload_bytes_total: :nat
      },
      idle_cycles_burned_per_day: :nat,
      module_hash: {:opt, :blob},
      reserved_cycles: :nat
    }

    IO.inspect(
      ICPAgent.call(factory, w, "canister_status", [:principal], [canister_id], return_type)
    )

  _ ->
    IO.puts("Usage: elixir canister_status.exs <canister_id>")
end
