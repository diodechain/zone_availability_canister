#!/usr/bin/env elixir
Mix.install([:icp_agent, :candid])
Code.eval_file("scripts/factory.ex")

case System.argv() do
  [canister_id] ->
    canister_id = ICPAgent.decode_textual(canister_id)

    Factory.start_canister(canister_id)
    |> IO.inspect()

  _ ->
    IO.puts("Usage: elixir start_canister.exs <canister_id>")
end
