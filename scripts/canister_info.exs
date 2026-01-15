#!/usr/bin/env elixir
Mix.install([{:icp_agent, "~> 0.1.8"}, :candid, {:diode_client, "~> 1.3.5"}])
:erlang.system_flag(:backtrace_depth, 30)
Logger.configure(level: :info)

defmodule DB do
  use GenServer

  def init(_db) do
    case File.read("./scripts/canisters.json") do
      {:ok, content} -> {:ok, Jason.decode!(content)}
      {:error, _} -> {:ok, %{}}
    end
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

  def handle_call({:get, row, key}, _from, db) do
    {:reply, get_in(db, [row, key]), db}
  end

  def handle_call(:save, _from, db) do
    File.write!("./scripts/canisters.json", Jason.encode!(db))
    {:reply, :ok, db}
  end

  def handle_cast({:set, row, key, value}, db) do
    new_row_value = Map.put(db[row] || %{}, key, value)
    {:noreply, Map.put(db, row, new_row_value)}
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

Task.async_stream(targets, fn dst ->
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
      IO.puts("#{dst} - #{version} - #{zone_id} - not found on-chain")
    else
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
          DiodeClient.Base16.decode(owner)
          |> DiodeClient.Contracts.BNS.resolve_address()
        end)

      IO.puts(
        "#{dst} - #{version} - #{zone_id} - #{chain} - #{contract_version} - #{owner} - #{name}"
      )
    end
  else
    IO.puts("#{dst} - #{inspect(version)} - not found")
  end

  DB.save()
end, timeout: :infinity, max_concurrency: 4)
|> Stream.run()
