#!/usr/bin/env elixir
Mix.install([{:icp_agent, "~> 0.1.9"}, :candid, {:diode_client, "~> 1.4.12"}])
Code.eval_file("scripts/factory.ex")
:erlang.system_flag(:backtrace_depth, 30)
Logger.configure(level: :info)

{opts, _args, invalid} =
  OptionParser.parse(System.argv(),
    strict: [upgrade: :boolean, canister: :string, index: :integer]
  )

if invalid != [] do
  IO.puts(:stderr, "Invalid options: #{inspect(invalid)}")
  System.halt(1)
end

upgrade? = Keyword.get(opts, :upgrade, false)

children =
  case Keyword.get(opts, :canister) do
    nil ->
      Factory.children() |> Enum.shuffle() |> Enum.with_index()

    canister_id ->
      [{canister_id, Keyword.get(opts, :index, 0)}]
  end

{upgrade?, wasms} =
  if upgrade? do
    DiodeClient.interface_add()

    build_wasm = fn name ->
      {_, 0} = System.cmd("dfx", ["build", "--check", name])
      File.read!(".dfx/local/canisters/#{name}/#{name}.wasm")
    end

    {
      true,
      %{
        cache: build_wasm.("ZoneAvailabilityCanister"),
        version: build_wasm.("ZoneAvailabilityCanisterVersion"),
        plain: build_wasm.("ZoneAvailabilityCanisterPlain")
      }
    }
  else
    {false, nil}
  end

# Listing / version queries are public; admin key only required for --upgrade.
w = if upgrade?, do: Factory.wallet(), else: Factory.query_wallet()

retry = fn child, fun ->
  with {:error, reason} <- fun.() do
    is_stopped = String.contains?(inspect(reason), "is stopped")
    is_out_of_cycles = String.contains?(inspect(reason), "out of cycles") || String.contains?(inspect(reason), "frozen")

    if is_stopped or is_out_of_cycles do
      Factory.refill(child) |> IO.inspect(label: "Refill #{child}")

      if is_stopped do
        Factory.start_canister(child) |> IO.inspect(label: "Start #{child}")
      end

      fun.()
    else
      {:error, reason}
    end
  end
end

memory_incompatible? = fn reason ->
  String.contains?(inspect(reason), "Memory-incompatible")
end

upgrade_canister = fn child, chain, zone_id, version, wasms ->
  strategies =
    case version do
      412 -> [:cache, :version, :plain]
      413 -> [:plain, :version, :cache]
      414 -> [:cache, :plain, :version]
      _ -> [:cache, :plain, :version]
    end

  Enum.reduce_while(strategies, {:error, :no_strategy}, fn strategy, _acc ->
    wasm = Map.fetch!(wasms, strategy)

    case retry.(child, fn -> Factory.upgrade(child, chain, zone_id, wasm) end) do
      {:error, reason} = error ->
        if memory_incompatible?.(reason) do
          {:cont, error}
        else
          {:halt, error}
        end

      ok ->
        {:halt, ok}
    end
  end)
end

version_cache =
  :ets.file2tab(~c"./scripts/version_cache.ets", [])
  |> case do
    {:ok, table} -> table
    {:error, {:read_error, _}} -> :ets.new(:version_cache, [:set, :public, :named_table])
  end

:ok = :ets.tab2file(version_cache, ~c"./scripts/version_cache.ets")

Task.Supervisor.start_link(name: MyApp.TaskSupervisor)

Task.Supervisor.async_stream_nolink(
  MyApp.TaskSupervisor,
  children,
  fn {child, index} ->
    if rem(index, 10) == 0 do
      ret = :ets.tab2file(version_cache, ~c"./scripts/version_cache.ets")
      IO.puts("Processing #{index} - #{child} - #{inspect(ret)}")
    end

    {version, cached?} =
      :ets.lookup(version_cache, child)
      |> case do
        [{_, version}] when is_integer(version) ->
          {version, true}

        _ ->
          case retry.(child, fn -> ICPAgent.query(child, w, "get_version") end) do
            {:error, reason} -> {"error: #{inspect(reason)}", false}
            [version] -> {version, false}
          end
      end

    :ets.insert(version_cache, {child, version})

    action =
      if upgrade? do
        target = Factory.target_zac_version()

        if is_integer(version) and version < target do
          [version] =
            if cached? do
              retry.(child, fn -> ICPAgent.query(child, w, "get_version") end)
            else
              [version]
            end

          [zone_id] = ICPAgent.query(child, w, "get_zone_id")
          chain = Factory.detect_chain(zone_id)

          if chain == nil do
            "#{version} - #{zone_id} -> not found on-chain"
          else
            upgrade_canister.(child, chain, zone_id, version, wasms)
            |> case do
              {:error, reason} ->
                "#{version} - #{zone_id} --> error: #{inspect(reason)}"

              _ ->
                :ets.insert(version_cache, {child, target})
                [new_zone_id] = ICPAgent.query(child, w, "get_zone_id")
                backend = Factory.get_rpc_backend(child)

                "#{version} - #{zone_id} --> upgraded v#{target} zone=#{new_zone_id} backend=#{inspect(backend)}"
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
        "#{version}"
      end

    if not String.contains?(action, "already upgraded") do
      IO.puts("#{index} - #{child} - #{action}")
    end
  end,
  timeout: :infinity,
  max_concurrency: 4
)
|> Stream.run()

:ets.tab2file(version_cache, ~c"./scripts/version_cache.ets")
