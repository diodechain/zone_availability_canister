#!/usr/bin/env elixir
Mix.install([
  {:diode_client, "~> 1.0"},
  {:cbor, "~> 1.0"},
  {:jason, "~> 1.4"},
  {:ex_sha3, "~> 0.1.1"},
  {:benchee, "~> 1.0"},
  {:finch, "~> 0.13.0"}
])

defmodule Candid do
  # https://github.com/dfinity/candid/blob/master/spec/Candid.md#core-grammar

  def decode("DIDL" <> term) do
    term
  end

  def encode(term) do
    ret = "DIDL" <> do_encode(term)
    IO.inspect({term, ret}, label: "encode")
    ret
  end

  def do_encode(list) when is_list(list) do
    len = length(list)
    leb128(len) <> Enum.join(Enum.map(list, &do_encode/1), "")
  end

  def do_encode(:null), do: sleb128(-1)
  def do_encode(:bool), do: sleb128(-2)
  def do_encode(:nat), do: sleb128(-3)
  def do_encode(:int), do: sleb128(-4)
  def do_encode(:nat8), do: sleb128(-5)
  def do_encode(:nat16), do: sleb128(-6)
  def do_encode(:nat32), do: sleb128(-7)
  def do_encode(:nat64), do: sleb128(-8)
  def do_encode(:int8), do: sleb128(-9)
  def do_encode(:int16), do: sleb128(-10)
  def do_encode(:int32), do: sleb128(-11)
  def do_encode(:int64), do: sleb128(-12)
  def do_encode(:float32), do: sleb128(-13)
  def do_encode(:float64), do: sleb128(-14)
  def do_encode(:text), do: sleb128(-15)
  def do_encode(:reserved), do: sleb128(-16)
  def do_encode(:empty), do: sleb128(-17)
  def do_encode(:principal), do: sleb128(-24)

  def leb128(number) do
    # https://en.wikipedia.org/wiki/LEB128#Unsigned_LEB128
    bits = for <<bit::size(1) <- :binary.encode_unsigned(number)>>, do: bit

    bits =
      case Enum.drop_while(bits, &(&1 == 0)) do
        [] -> [0]
        rest -> rest
      end

    do_leb128(bits, false)
  end

  def sleb128(number) do
    # https://en.wikipedia.org/wiki/LEB128#Unsigned_LEB128
    is_signed = number < 0
    number = abs(number)
    bits = for <<bit::size(1) <- :binary.encode_unsigned(number)>>, do: bit
    bits = [0 | Enum.drop_while(bits, &(&1 == 0))]
    do_leb128(bits, is_signed)
  end

  defp do_leb128(bits, is_signed) do
    len = length(bits)
    missing = ceil(len / 7) * 7 - len
    padded = List.duplicate(0, missing) ++ bits

    padded =
      if is_signed do
        len = length(padded)
        padded = Enum.map(padded, fn bit -> if bit == 0, do: 1, else: 0 end)

        <<num::unsigned-size(len)>> =
          Enum.reduce(padded, "", fn bit, acc -> <<acc::bitstring, bit::size(1)>> end)

        for <<(bit::size(1) <- <<num + 1::unsigned-size(len)>>)>>, do: bit
      else
        padded
      end

    Enum.chunk_every(padded, 7)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      marker = if index == 0, do: <<0::size(1)>>, else: <<1::size(1)>>
      [marker | Enum.map(chunk, &<<&1::size(1)>>)]
    end)
    |> Enum.reverse()
    |> List.flatten()
    |> Enum.reduce("", fn bit, acc -> <<acc::bitstring, bit::bitstring>> end)
  end
end

defmodule Test do
  alias DiodeClient.Wallet

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

  def query(canister, wallet, query) do
    request_id = hash_of_map(query)
    sig = wallet_sign(wallet, domain_separator("ic-request") <> request_id)

    query = %{
      "content" => query,
      "sender_pubkey" => cbor_bytes(wallet_der(wallet)),
      "sender_sig" => cbor_bytes(sig)
    }

    curl("#{host()}/api/v2/canister/#{canister}/query", query)
  end

  defp curl(host, opayload, method \\ :post, headers \\ []) do
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

    if print_requests?() do
      IO.puts("")
      IO.puts("POST #{String.replace_prefix(host, host(), "")}")

      if method == :post do
        IO.puts(">> #{inspect(opayload)}")
      end
    end

    {:ok, tag, ""} = CBOR.decode(ret.body)

    if print_requests?() do
      IO.puts("<< #{inspect(tag.value)}")
    end

    tag.value
  end

  def print_requests?() do
    :persistent_term.get(:print_requests?, true)
  end

  def h(number) when is_integer(number), do: h(Candid.leb128(number))
  def h(%CBOR.Tag{tag: :bytes, value: data}), do: h(data)
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
    # IO.inspect(public, label: "public")

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
    wallet =
      wallet_from_pem("""
      -----BEGIN EC PRIVATE KEY-----
      MHQCAQEEIGfKHuyoCCCbEXb0789MIdWiCIpZo1LaKApv95SSIaWPoAcGBSuBBAAK
      oUQDQgAEahC99Avid7r8D6kIeLjjxJ8kwdJRy5nPrN9o18P7xHT95i0JPr5ivc9v
      CB8vG2s97NB0re2MhqvdWgradJZ8Ow==
      -----END EC PRIVATE KEY-----
      """)

    reftext = "42gbo-uiwfn-oq452-ql6yp-4jsqn-a6bxk-n7l4z-ni7os-yptq6-3htob-vqe"

    <<_crc32::binary-size(4), refbin::binary>> =
      String.replace(reftext, "-", "")
      |> Base.decode32!(case: :lower, padding: false)

    IO.inspect(refbin, label: "refbin")
    idsize = byte_size(wallet_id(wallet))
    ^idsize = byte_size(refbin)
    ^refbin = IO.inspect(wallet_id(wallet), label: "wallet_id")
    ^reftext = IO.inspect(wallet_textual(wallet), label: "wallet_textual")

    <<0xE5, 0x8E, 0x26>> = Candid.leb128(624_485)
    <<0xC0, 0xBB, 0x78>> = Candid.sleb128(-123_456)
    <<0x7F>> = Candid.sleb128(-1)

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

    %{"certified_height" => height, "replica_health_status" => "healthy", "root_key" => root_key} =
      status()

    IO.puts("certified_height: #{height}")
    IO.puts("root_key: #{inspect(Base.encode16(root_key.value))}")

    w = Wallet.new()
    IO.puts("wallet_textual: #{wallet_textual(w)}")

    canister_id = "bkyz2-fmaaa-aaaaa-qaaaq-cai"

    <<_crc32::binary-size(4), canister_bin_id::binary>> =
      String.replace(canister_id, "-", "") |> Base.decode32!(case: :lower, padding: false)

    %{"reply" => %{"arg" => ret}} =
      query(canister_id, w, %{
        "request_type" => "query",
        "canister_id" => cbor_bytes(canister_bin_id),
        "method_name" => "get_max_message_id",
        # "arg" => cbor_bytes(Candid.encode([])),
        "arg" => cbor_bytes("DIDL\x00\x00"),
        "sender" => cbor_bytes(wallet_id(w)),
        "ingress_expiry" => System.os_time(:nanosecond) + 1000 * 1000 * 1000
      })

      0 = Candid.decode(ret.value)
  end

  def cbor_bytes(data) do
    %CBOR.Tag{tag: :bytes, value: data}
  end

  def benchmark(parallel \\ 1) do
    :persistent_term.put(:print_requests?, false)

    Benchee.run(
      %{
        "test_name" => fn -> :ok end
      },
      parallel: parallel,
      time: 5
    )
  end
end

Finch.start_link(name: TestFinch)

case System.argv() do
  ["bench"] ->
    Test.ensure_service()
    Test.benchmark()
    System.halt(0)

  ["benchp"] ->
    Test.ensure_service()
    Test.benchmark(20)
    System.halt(0)

  [] ->
    :ok

  _other ->
    IO.puts("Wrong argument. Try <none>, dev, lt or dev")
    System.halt(1)
end

Test.ensure_service()
Test.run()
IO.puts("😋😋Tests finished!")
