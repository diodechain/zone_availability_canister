#!/usr/bin/env elixir
Mix.install([
  {:candid, "~> 1.0"},
  {:diode_client, "~> 1.0"},
  {:cbor, "~> 1.0"},
  {:jason, "~> 1.4"},
  {:ex_sha3, "~> 0.1.1"},
  {:benchee, "~> 1.0"},
  {:finch, "~> 0.13.0"}
])

defmodule Test do
  alias DiodeClient.Wallet

  def default_canister_id() do
    "bkyz2-fmaaa-aaaaa-qaaaq-cai"
  end

  def default_host() do
    "http://127.0.0.1:4943"
  end

  def host() do
    System.get_env("ICP_DOMAIN", default_host())
  end

  def service?(port \\ nil) do
    uri = URI.parse(host())
    host = uri.host
    port = port || uri.port

    case :gen_tcp.connect(~c"#{host}", port, mode: :binary) do
      {:ok, socket} -> :gen_tcp.close(socket) == :ok
      _err -> false
    end
  end

  def ensure_service() do
    if not service?() do
      {:os_pid, pid} =
        Port.open({:spawn, "dfx start --clean"}, [:binary, :exit_status, :use_stdio])
        |> :erlang.port_info(:os_pid)

      System.at_exit(fn _ -> System.cmd("kill", ["#{pid}"]) end)
      await_service()
      {_, 0} = System.cmd("bash", ["deploy.sh"])
    end
  end

  def await_service(n \\ 0) do
    receive do
      {_port, {:exit_status, status}} ->
        IO.puts("`dfx start --clean` exited unexpectedly with status #{status}")
        System.halt(1)
    after
      1000 -> :ok
    end

    if not service?() do
      await_service(n + 1)
    end
  end

  def status() do
    curl("#{host()}/api/v2/status", %{}, :get)
  end

  def domain_separator(name) do
    <<byte_size(name), name::binary>>
  end

  defp sign_query(wallet, query) do
    query =
      Map.merge(query, %{
        "ingress_expiry" => System.os_time(:nanosecond) + 1000 * 1000 * 1000,
        "sender" => cbor_bytes(wallet_id(wallet))
      })

    request_id = hash_of_map(query)
    sig = wallet_sign(wallet, domain_separator("ic-request") <> request_id)

    {request_id,
     %{
       "content" => utf8_to_list(query),
       "sender_pubkey" => cbor_bytes(wallet_der(wallet)),
       "sender_sig" => cbor_bytes(sig)
     }}
  end

  def utf8_to_list(map) when is_map(map) and not is_struct(map) do
    Enum.map(map, fn {key, value} -> {key, utf8_to_list(value)} end) |> Map.new()
  end

  def utf8_to_list(list) when is_list(list) do
    Enum.map(list, &utf8_to_list/1)
  end

  def utf8_to_list({:utf8, binary}) when is_binary(binary), do: binary
  def utf8_to_list(other), do: other

  def call(canister_id, wallet, method, types \\ [], args \\ []) do
    {request_id, query} =
      sign_query(wallet, %{
        "request_type" => "call",
        "canister_id" => cbor_bytes(decode_textual(canister_id)),
        "method_name" => method,
        "arg" => cbor_bytes(Candid.encode_parameters(types, args))
      })

    ret = curl("#{host()}/api/v3/canister/#{canister_id}/call", query)

    if ret["status"] == "replied" do
      # read_state(canister_id, wallet, [["request_status", cbor_bytes(request_id), "reply"]])
      {:ok, %{value: value}, ""} = CBOR.decode(ret["certificate"].value)
      tree = flatten_tree(value["tree"])

      reply = tree["request_status"][request_id]["reply"]

      if reply != nil do
        {decoded, ""} = Candid.decode_parameters(reply)
        decoded
      else
        tree
      end
    else
      ret
    end
  end

  defp flatten_tree(tree) do
    do_flatten_tree(tree)
    |> List.wrap()
    |> mapify()
  end

  defp mapify(list) when is_list(list), do: Enum.map(list, &mapify/1) |> Map.new()
  defp mapify({key, value}), do: {key, mapify(value)}
  defp mapify(other), do: other

  defp do_flatten_tree([1 | list]),
    do: Enum.map(list, &do_flatten_tree/1) |> Enum.reject(&is_nil/1) |> List.flatten()

  defp do_flatten_tree([2, key, values]), do: {key.value, do_flatten_tree(values)}
  defp do_flatten_tree([3, value]), do: value.value
  defp do_flatten_tree([4, _sig]), do: nil

  def query(canister_id, wallet, method, types \\ [], args \\ []) do
    {_request_id, query} =
      sign_query(wallet, %{
        "request_type" => "query",
        "canister_id" => cbor_bytes(decode_textual(canister_id)),
        "method_name" => method,
        "arg" => cbor_bytes(Candid.encode_parameters(types, args))
      })

    %{"reply" => %{"arg" => ret}} = curl("#{host()}/api/v2/canister/#{canister_id}/query", query)

    {ret, ""} = Candid.decode_parameters(ret.value)
    ret
  end

  def read_state(canister_id, wallet, paths) do
    {_request_id, query} =
      sign_query(wallet, %{
        "request_type" => "read_state",
        "paths" => paths
      })

    %{"reply" => %{"arg" => ret}} =
      curl("#{host()}/api/v2/canister/#{canister_id}/read_state", query)

    {ret, ""} = Candid.decode_parameters(ret.value)
    ret
  end

  defp curl(host, opayload, method \\ :post, headers \\ []) do
    now = System.os_time(:millisecond)
    payload = CBOR.encode(opayload)
    {:ok, _decoded, ""} = CBOR.decode(payload)

    {:ok, ret} =
      Finch.build(
        method,
        host,
        [{"Content-Type", "application/cbor"}] ++ headers,
        if(method == :post, do: payload)
      )
      |> Finch.request(TestFinch)

    p1 = System.os_time(:millisecond)

    if print_requests?() do
      method = opayload["content"]["method_name"] || ""

      IO.puts(
        "POST #{method} #{String.replace_prefix(host, host(), "")} (#{byte_size(payload)} bytes request)"
      )

      # if method == :post do
      #   IO.puts(">> #{inspect(opayload)}")
      # end
    end

    {:ok, tag, ""} = CBOR.decode(ret.body)

    p2 = System.os_time(:millisecond)

    if print_requests?() do
      # IO.puts("<< #{inspect(tag.value)}")
      IO.puts(
        "POST latency: #{p2 - now}ms http: #{p1 - now}ms (#{byte_size(ret.body)} bytes response)"
      )

      IO.puts("")
    end

    tag.value
  end

  def print_requests?() do
    :persistent_term.get(:print_requests?, true)
  end

  def h([]), do: :crypto.hash(:sha256, "")
  def h(list) when is_list(list), do: :crypto.hash(:sha256, Enum.join(Enum.map(list, &h/1), ""))
  def h(number) when is_integer(number), do: h(LEB128.encode_unsigned(number))
  def h(%CBOR.Tag{tag: :bytes, value: data}), do: h(data)
  def h({:utf8, data}) when is_binary(data), do: h(data)
  def h(data) when is_binary(data), do: :crypto.hash(:sha256, data)

  # https://internetcomputer.org/docs/current/references/ic-interface-spec#request-id
  def hash_of_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      h(key) <> h(value)
    end)
    |> Enum.sort()
    |> Enum.join("")
    |> h()
  end

  def wallet_id(wallet) do
    # https://internetcomputer.org/docs/current/references/ic-interface-spec#id-classes
    :crypto.hash(:sha224, wallet_der(wallet)) <> <<2>>
  end

  def crc32(data) do
    <<:erlang.crc32(data)::size(32)>>
  end

  def wallet_textual(wallet) do
    id = wallet_id(wallet)

    Base.encode32(crc32(id) <> id, case: :lower, padding: false)
    |> String.to_charlist()
    |> Enum.chunk_every(5)
    |> Enum.join("-")
  end

  def wallet_sign(wallet, data) do
    <<_recovery, rest::binary>> = DiodeClient.Secp256k1.sign(Wallet.privkey!(wallet), data, :sha)
    rest
  end

  def wallet_der(wallet) do
    public = Wallet.pubkey_long!(wallet)

    term =
      {:OTPSubjectPublicKeyInfo,
       {:PublicKeyAlgorithm, {1, 2, 840, 10_045, 2, 1}, {:namedCurve, {1, 3, 132, 0, 10}}},
       public}

    :public_key.pkix_encode(:OTPSubjectPublicKeyInfo, term, :otp)
  end

  def wallet_from_pem(pem) do
    [{:ECPrivateKey, der, _}] = :public_key.pem_decode(pem)

    {:ECPrivateKey, 1, privkey, {:namedCurve, {1, 3, 132, 0, 10}}, pubkey, :asn1_NOVALUE} =
      :public_key.der_decode(:ECPrivateKey, der)

    wallet = Wallet.from_privkey(privkey)
    ^pubkey = Wallet.pubkey_long!(wallet)
    wallet
  end

  def run() do
    {decoded, ""} =
      <<68, 73, 68, 76, 1, 107, 2, 156, 194, 1, 127, 229, 142, 180, 2, 113, 1, 0, 0>>
      |> Candid.decode_parameters()

    ^decoded = [{Candid.namehash("ok"), nil}]

    {[{0, 1}], ""} =
      <<68, 73, 68, 76, 1, 108, 2, 0, 121, 1, 121, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0>>
      |> Candid.decode_parameters()

    wallet =
      wallet_from_pem("""
      -----BEGIN EC PRIVATE KEY-----
      MHQCAQEEIGfKHuyoCCCbEXb0789MIdWiCIpZo1LaKApv95SSIaWPoAcGBSuBBAAK
      oUQDQgAEahC99Avid7r8D6kIeLjjxJ8kwdJRy5nPrN9o18P7xHT95i0JPr5ivc9v
      CB8vG2s97NB0re2MhqvdWgradJZ8Ow==
      -----END EC PRIVATE KEY-----
      """)

    reftext = "42gbo-uiwfn-oq452-ql6yp-4jsqn-a6bxk-n7l4z-ni7os-yptq6-3htob-vqe"
    refbin = decode_textual(reftext)

    idsize = byte_size(wallet_id(wallet))
    ^idsize = byte_size(refbin)
    ^refbin = wallet_id(wallet)
    ^reftext = wallet_textual(wallet)
    IO.puts("wallet textual: #{reftext}")

    "0xdb8e57abc8cda1525d45fdd2637af091bc1f28b35819a40df71517d1501f2c76" =
      h(1_685_570_400_000_000_000) |> DiodeClient.Base16.encode()

    "0x6c0b2ae49718f6995c02ac5700c9c789d7b7862a0d53e6d40a73f1fcd2f70189" =
      h("DIDL\x00\xFD*") |> DiodeClient.Base16.encode()

    "0x1d1091364d6bb8a6c16b203ee75467d59ead468f523eb058880ae8ec80e2b101" =
      hash_of_map(%{
        "request_type" => "call",
        "sender" => <<0x04>>,
        "ingress_expiry" => 1_685_570_400_000_000_000,
        "canister_id" => "\x00\x00\x00\x00\x00\x00\x04\xD2",
        "method_name" => "hello",
        "arg" => "DIDL\x00\xFD*"
      })
      |> DiodeClient.Base16.encode()

    w = Wallet.from_privkey(DiodeClient.Base16.decode("0xb6dbce9418872c4b8f5a10a5778e247c60cdb0265f222c0bfdbe565cfe63d64a"))
    IO.puts("wallet_textual: #{wallet_textual(w)}")
    IO.puts("wallet_address: #{Wallet.printable(w)}")
    canister_id = default_canister_id()

    [{0, 1}] = call(canister_id, w, "test_record_output", [], [])

    [3] =
      call(canister_id, w, "test_record_input", [{:record, [{0, :nat32}, {1, :nat32}]}], [{1, 2}])

    identity_contract = DiodeClient.Base16.decode("0x08ff68fe9da498223d4fc953bc4c336ec5726fec")
    [200] = call(canister_id, w, "update_identity_role", [:blob, :blob], [Wallet.pubkey_long!(w), identity_contract])
    # test_batch_write(w, canister_id)

    %{"certified_height" => height, "replica_health_status" => "healthy", "root_key" => root_key} =
      status()

    IO.puts("certified_height: #{height}")
    IO.puts("root_key: #{inspect(Base.encode16(root_key.value))}")

    [n] = query(canister_id, w, "get_max_message_id")

    message = "hello diode #{n}"
    key_id = Wallet.address!(w)
    isOk(call(canister_id, w, "add_message", [:blob, :blob], [key_id, message]))
    n2 = n + 1
    [^n2] = query(canister_id, w, "get_max_message_id")

    message = "hello diode #{n2}"
    key_id = Wallet.address!(w)
    isOk(call(canister_id, w, "add_message", [:blob, :blob], [key_id, message]))
    n3 = n2 + 1
    [^n3] = query(canister_id, w, "get_max_message_id")

    test_batch_write(w, canister_id, 10)
    {time, _} = :timer.tc(fn -> test_batch_write(w, canister_id, 10_000) end)
    IO.puts("Writing 10k messages took: #{div(time, 1000)} milliseconds")
    test_batch_read(w, canister_id, 1, 1000)
  end

  def test_batch_write(w, canister_id, size \\ 10) do
    key_id = Wallet.address!(w)
    n = System.os_time(:nanosecond)
    type_spec = [{:vec, {:record, [{0, :blob}, {1, :blob}]}}]

    messages =
      Enum.reduce(1..size, [], fn i, acc ->
        [{key_id, "hello diode batch #{n}/#{i}"} | acc]
      end)
      |> Enum.reverse()

    isOk(call(canister_id, w, "add_messages", type_spec, [messages]))
  end

  def test_batch_read(w, canister_id, start, size \\ 10) do
    [messages] =
      query(canister_id, w, "get_messages_by_range", [:nat32, :nat32], [start, start + size - 1])

    ^size = length(messages)
    messages
  end

  def isOk([{tag, nil}]) do
    if tag != Candid.namehash("ok") do
      raise "Expected ok, got #{tag}"
    end
  end

  def isOk(other), do: raise("Expected [{ok, nil}] variant, got #{inspect(other)}")

  def cbor_bytes(data) do
    %CBOR.Tag{tag: :bytes, value: data}
  end

  def decode_textual(canister_id) do
    <<_crc32::binary-size(4), canister_bin_id::binary>> =
      String.replace(canister_id, "-", "") |> Base.decode32!(case: :lower, padding: false)

    canister_bin_id
  end

  def write_benchmark(parallel \\ 1) do
    :persistent_term.put(:print_requests?, false)
    w = Wallet.new()
    canister_id = default_canister_id()

    [10, 100, 1000, 10000]
    |> Enum.map(fn size ->
      {"insert #{size}", fn -> test_batch_write(w, canister_id, size) end}
    end)
    |> Benchee.run(
      parallel: parallel,
      time: 30
    )
  end

  def anomaly_benchmark() do
    :persistent_term.put(:print_requests?, false)
    w = Wallet.new()
    canister_id = default_canister_id()
    test_batch_write(w, canister_id, 20000)
    cnt = :atomics.new(1, [])
    next = fn -> rem(:atomics.add_get(cnt, 1, 1), 10_000) + 1 end

    :persistent_term.put(:print_requests?, true)

    [650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660]
    |> Enum.map(fn size ->
      IO.puts("Reading #{size} messages")
      test_batch_read(w, canister_id, next.(), size)
    end)

    :persistent_term.put(:print_requests?, false)
    System.halt(0)
  end

  def read_benchmark(parallel \\ 1) do
    :persistent_term.put(:print_requests?, false)
    w = Wallet.new()
    canister_id = default_canister_id()
    test_batch_write(w, canister_id, 20000)
    cnt = :atomics.new(1, [])
    next = fn -> rem(:atomics.add_get(cnt, 1, 1), 10_000) + 1 end

    [10, 100, 1000, 10000]
    |> Enum.map(fn size ->
      {"read #{size}", fn -> test_batch_read(w, canister_id, next.(), size) end}
    end)
    |> Benchee.run(
      parallel: parallel,
      time: 5
    )
  end
end

Finch.start_link(name: TestFinch)
:erlang.system_flag(:backtrace_depth, 30)

case System.argv() do
  ["write_bench"] ->
    Test.ensure_service()
    Test.write_benchmark()
    System.halt(0)

  ["read_bench"] ->
    Test.ensure_service()
    Test.read_benchmark()
    System.halt(0)

  ["anomaly"] ->
    Test.ensure_service()
    Test.anomaly_benchmark()
    System.halt(0)

  ["test"] ->
    :ok

  [] ->
    :ok

  _other ->
    IO.puts("Wrong argument. Try <none>, test, write_bench, read_bench")
    System.halt(1)
end

Test.ensure_service()
Test.run()
IO.puts("😋😋Tests finished!")
