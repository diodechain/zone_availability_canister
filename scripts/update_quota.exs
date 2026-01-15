#!/usr/bin/env elixir
Mix.install([{:icp_agent, "~> 0.1.8"}, :candid, {:diode_client, "~> 1.3.5"}])
Code.eval_file("scripts/factory.ex")

case System.argv() do
  ["default"] ->
    # 1 trillion cycles per hour max (~1.30 USD)
    new_quota = 1_000_000_000_000
    duration_in_seconds = 60 * 60
    Factory.update_aggregate_quota_settings(new_quota, duration_in_seconds)

  [new_quota] ->
    new_quota = String.to_integer(new_quota)
    Factory.update_aggregate_quota_settings(new_quota)

  [new_quota, duration_in_seconds] ->
    new_quota = String.to_integer(new_quota)
    duration_in_seconds = String.to_integer(duration_in_seconds)
    Factory.update_aggregate_quota_settings(new_quota, duration_in_seconds)

  _ ->
    IO.puts("Usage: elixir update_quota.exs <new_quota> [duration_in_seconds]")
end
