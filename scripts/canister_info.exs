#!/usr/bin/env elixir
Mix.install([{:icp_agent, "~> 0.1.8"}, :candid, {:diode_client, "~> 1.3.5"}])
:erlang.system_flag(:backtrace_depth, 30)
Logger.configure(level: :info)

defmodule DB do
  use GenServer

  def init(_db) do
    db = case File.read("./scripts/canisters.json") do
      {:ok, content} -> Jason.decode!(content)
      {:error, _} -> %{}
    end

    {:ok, %{db: db, last_save: System.os_time(:second)}}
  end

  def fetch(row, key, default_fun) do
    key = "#{key}"

    case GenServer.call(__MODULE__, {:get, row, key}) do
      nil ->
        value = default_fun.()

        case value do
          nil -> nil
          {:error, _reason} -> nil
          _ -> GenServer.cast(__MODULE__, {:set, row, key, value})
        end

        value

      value ->
        value
    end
  end

  def save() do
    GenServer.call(__MODULE__, :save)
  end

  def handle_call({:get, row, key}, _from, state = %{db: db}) do
    {:reply, get_in(db, [row, key]), state}
  end

  def handle_call(:save, _from, state = %{db: db}) do
    File.write!("./scripts/canisters.json", Jason.encode!(db))
    {:reply, :ok, %{state | last_save: System.os_time(:second)}}
  end

  def handle_cast({:set, row, key, value}, state = %{db: db, last_save: last_save}) do
    new_row_value = Map.put(db[row] || %{}, key, value)
    state = %{state | db: Map.put(db, row, new_row_value)}
    if System.os_time(:second) - last_save > 60 do
      File.write!("./scripts/canisters.json", Jason.encode!(db))
      {:noreply, %{state | last_save: System.os_time(:second)}}
    else
      {:noreply, state}
    end
  end
end

GenServer.start_link(DB, nil, name: DB)
w = DiodeClient.Wallet.new()
DiodeClient.interface_add()

targets =
  case System.argv() do
    ["--all"] ->
      w =
        File.read!("diode_glmr.key")
        |> String.trim()
        |> DiodeClient.Base16.decode()
        |> DiodeClient.Wallet.from_privkey()

      factory = "dgnum-qiaaa-aaaao-qj3ta-cai"

      [children] =
        ICPAgent.query(factory, w, "get_cycles_manager_children", [], [], [{:vec, :principal}])

      Enum.map(children, &ICPAgent.encode_textual/1)

    [dst] ->
      [dst]

    _ ->
      IO.puts("Usage: elixir canister_info.exs [--all | <destination>]")
      System.halt(1)
  end

Enum.with_index(targets, 1)
|> Task.async_stream(fn {dst, index} ->
  version =
    DB.fetch(dst, :canister_version, fn -> ICPAgent.query(dst, w, "get_version", [], [], :nat) end)

  if is_integer(version) do
    zone_id =
      DB.fetch(dst, :zone_id, fn -> ICPAgent.query(dst, w, "get_zone_id", [], [], :text) end)

    account = DiodeClient.Base16.decode(zone_id)

    chain =
      DB.fetch(dst, :chain, fn ->
        Enum.find(
          [DiodeClient.Shell.Moonbeam, DiodeClient.Shell.OasisSapphire, DiodeClient.Shell],
          fn shell ->
            shell.get_account_root(account) != nil
          end
        )
      end)

    if chain == nil do
      [index, dst, version, zone_id, "not found on-chain"]
    else
      chain = if is_binary(chain), do: String.to_atom(chain), else: chain

      contract_version =
        DB.fetch(dst, :contract_version, fn ->
          chain.call(account, "Version", [], [], result_types: "uint256")
        end)

      owner =
        DB.fetch(dst, :owner, fn ->
          chain.call(account, "owner", [], [], result_types: "address")
          |> DiodeClient.Base16.encode()
        end)

      name =
        DB.fetch(dst, :owner_name, fn ->
          if owner == "0x000000000000000000000000000000000000dead" do
            "(0xDEAD)"
          else
            DiodeClient.Base16.decode(owner)
            |> DiodeClient.Contracts.BNS.resolve_address()
          end
        end)

      [index, dst, version, zone_id, chain, contract_version, owner, name]
    end
  else
    [index, dst, version]
  end
end, timeout: :infinity, max_concurrency: 4)
|> Stream.each(fn {:ok, row} ->
  line =
    Enum.map_join(row, "\t", fn
      {:error, reason} -> inspect(reason)
      value -> to_string(value)
    end)
  IO.puts(line)
end)
|> Stream.run()

DB.save()
