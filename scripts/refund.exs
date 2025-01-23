#!/usr/bin/env elixir
Mix.install([:icp_agent, {:candid, "~> 1.1.0", override: true}])
factory = "dgnum-qiaaa-aaaao-qj3ta-cai"
IO.inspect(ICPAgent.call(factory, DiodeClient.Wallet.new(), "refund"))
