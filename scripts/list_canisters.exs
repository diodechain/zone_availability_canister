#!/usr/bin/env elixir
Mix.install([{:icp_agent, "~> 0.1.8"}, :candid, {:diode_client, "~> 1.3.5"}])
Code.eval_file("scripts/factory.ex")
:erlang.system_flag(:backtrace_depth, 30)
Logger.configure(level: :info)

children = Factory.children() |> Enum.with_index()

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

w = Factory.wallet()

retry = fn child, fun ->
  with {:error, reason} <- fun.() do
    is_stopped = String.contains?(inspect(reason), "is stopped")
    is_out_of_cycles = String.contains?(inspect(reason), "out of cycles")

    if is_stopped or is_out_of_cycles do
      Factory.refill(child) |> IO.inspect(label: "Refill")
      if is_stopped do
        Factory.start_canister(child) |> IO.inspect(label: "Start")
      end

      fun.()
    else
      {:error, reason}
    end
  end
end

Task.async_stream(
  children,
  fn {child, index} ->
    if rem(index, 10) == 0 do
      IO.puts("Processing #{index} - #{child}")
    end

    action =
      if upgrade? do
        version =
          case retry.(child, fn -> ICPAgent.query(child, w, "get_version") end) do
            {:error, reason} -> "error: #{inspect(reason)}"
            [version] -> version
          end

        if is_integer(version) and version < 411 do
          [zone_id] = ICPAgent.query(child, w, "get_zone_id")
          account = DiodeClient.Base16.decode(zone_id)

          chain =
            cond do
              DiodeClient.Shell.Moonbeam.get_account_root(account) != nil -> "moonbeam"
              DiodeClient.Shell.get_account_root(account) != nil -> "diode"
              DiodeClient.Shell.OasisSapphire.get_account_root(account) != nil -> "oasis"
              true -> nil
            end

          if chain == nil do
            "#{version} - #{zone_id} -> not found on-chain"
          else
            retry.(child, fn -> Factory.upgrade(child, chain, zone_id, wasm) end)
            |> case do
              {:error, reason} ->
                "#{version} - #{zone_id} --> error: #{inspect(reason)}"

              _ ->
                "#{version} - #{zone_id} --> upgraded"
            end
          end
        else
          if is_integer(version) do
            "#{version} -> already upgraded"
          else
            "error: #{inspect(version)}"
          end
        end
      else
        "none"
      end

    if not String.contains?(action, "already upgraded") do
      IO.puts("#{index} - #{child} - #{action}")
    end
  end,
  timeout: :infinity,
  max_concurrency: 2
)
|> Stream.run()
