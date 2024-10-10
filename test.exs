#!/usr/bin/env elixir
Mix.install([
  {:leb128, "~> 1.0"},
  {:diode_client, "~> 1.0"},
  {:cbor, "~> 1.0"},
  {:jason, "~> 1.4"},
  {:ex_sha3, "~> 0.1.1"},
  {:benchee, "~> 1.0"},
  {:finch, "~> 0.13.0"}
])

defmodule Candid do
  # https://github.com/dfinity/candid/blob/master/spec/Candid.md#core-grammar

  def decode_parameters("DIDL" <> term) do
    {_definition_table, rest} = decode_list(term)
    {argument_types, rest} = decode_list(rest)
    decode_arguments(argument_types, rest)
  end

  defp decode_list(term) do
    {len, rest} = LEB128.decode_unsigned!(term)
    decode_list_items(len, rest, [])
  end

  defp decode_list_items(0, rest, acc) do
    {acc, rest}
  end

  defp decode_list_items(n, rest, acc) do
    {item, rest} = decode(rest)
    decode_list_items(n - 1, rest, acc ++ [item])
  end

  defp decode_arguments([type | types], rest) do
    {value, rest} = decode_type(type, rest)
    {values, rest} = decode_arguments(types, rest)
    {[value | values], rest}
  end

  defp decode_arguments([], rest) do
    {[], rest}
  end

  def decode_type(:nat32, <<value::unsigned-little-size(32), rest::binary>>), do: {value, rest}
  def decode_type(:int32, <<value::signed-little-size(32), rest::binary>>), do: {value, rest}
  def decode_type(:nat64, <<value::unsigned-little-size(64), rest::binary>>), do: {value, rest}
  def decode_type(:int64, <<value::signed-little-size(64), rest::binary>>), do: {value, rest}
  def decode_type(:nat8, <<value::unsigned-little-size(8), rest::binary>>), do: {value, rest}
  def decode_type(:int8, <<value::signed-little-size(8), rest::binary>>), do: {value, rest}
  def decode_type(:nat16, <<value::unsigned-little-size(16), rest::binary>>), do: {value, rest}
  def decode_type(:int16, <<value::signed-little-size(16), rest::binary>>), do: {value, rest}
  def decode_type(:nat32, <<value::unsigned-little-size(32), rest::binary>>), do: {value, rest}
  def decode_type(:int32, <<value::signed-little-size(32), rest::binary>>), do: {value, rest}
  def decode_type(:nat, rest), do: LEB128.decode_unsigned!(rest)
  def decode_type(:int, rest), do: LEB128.decode_unsigned!(rest)

  def decode_type(type, rest) do
    # https://github.com/dfinity/candid/blob/master/spec/Candid.md#core-grammar
    raise "unimplemented type: #{inspect({type, rest})}"
  end

  def encode_parameters(types, values) do
    if length(types) != length(values) do
      raise "types and values must have the same length"
    end

    definition_table = encode_list([], &encode_type/1)
    argument_types = encode_list(types, &encode_type/1)

    values =
      Enum.zip(types, values)
      |> Enum.map(fn {type, value} -> encode_type_value(type, value) end)
      |> Enum.join("")

    "DIDL" <> definition_table <> argument_types <> values
  end

  def encode_list(list, fun) when is_list(list) do
    len = length(list)
    LEB128.encode_unsigned(len) <> Enum.join(Enum.map(list, fun), "")
  end

  def encode_type_value(:null, _), do: ""

  def encode_type_value(:bool, bool),
    do:
      (if bool do
         <<1>>
       else
         <<0>>
       end)

  def encode_type_value(:nat, nat), do: LEB128.encode_unsigned(nat)
  def encode_type_value(:int, int), do: LEB128.encode_signed(int)
  def encode_type_value(:nat8, nat8), do: <<nat8>>
  def encode_type_value(:nat16, nat16), do: <<nat16::unsigned-little-size(16)>>
  def encode_type_value(:nat32, nat32), do: <<nat32::unsigned-little-size(32)>>
  def encode_type_value(:nat64, nat64), do: <<nat64::unsigned-little-size(64)>>
  def encode_type_value(:int8, int8), do: <<int8>>
  def encode_type_value(:int16, int16), do: <<int16::signed-little-size(16)>>
  def encode_type_value(:int32, int32), do: <<int32::signed-little-size(32)>>
  def encode_type_value(:int64, int64), do: <<int64::signed-little-size(64)>>
  def encode_type_value(:float32, float32), do: <<float32::signed-little-size(32)>>
  def encode_type_value(:float64, float64), do: <<float64::signed-little-size(64)>>
  def encode_type_value(:text, text), do: text
  def encode_type_value(:reserved, _), do: ""
  # def encode_type_value(:empty, _), do: ""
  # def encode_type_value(:principal, principal), do: principal
  def encode_type_value({:vec, :nat8}, binary) when is_binary(binary),
    do: LEB128.encode_unsigned(byte_size(binary)) <> binary

  def encode_type_value({:vec, type}, values),
    do: encode_list(values, &encode_type_value(type, &1))

  def encode_type_value(:blob, values), do: encode_type_value({:vec, :nat8}, values)
  def encode_type_value({:opt, _type}, nil), do: <<0>>
  def encode_type_value({:opt, type}, value), do: <<1>> <> encode_type_value(type, value)

  def encode_type(:null), do: LEB128.encode_signed(-1)
  def encode_type(:bool), do: LEB128.encode_signed(-2)
  def encode_type(:nat), do: LEB128.encode_signed(-3)
  def encode_type(:int), do: LEB128.encode_signed(-4)
  def encode_type(:nat8), do: LEB128.encode_signed(-5)
  def encode_type(:nat16), do: LEB128.encode_signed(-6)
  def encode_type(:nat32), do: LEB128.encode_signed(-7)
  def encode_type(:nat64), do: LEB128.encode_signed(-8)
  def encode_type(:int8), do: LEB128.encode_signed(-9)
  def encode_type(:int16), do: LEB128.encode_signed(-10)
  def encode_type(:int32), do: LEB128.encode_signed(-11)
  def encode_type(:int64), do: LEB128.encode_signed(-12)
  def encode_type(:float32), do: LEB128.encode_signed(-13)
  def encode_type(:float64), do: LEB128.encode_signed(-14)
  def encode_type(:text), do: LEB128.encode_signed(-15)
  def encode_type(:reserved), do: LEB128.encode_signed(-16)
  def encode_type(:empty), do: LEB128.encode_signed(-17)
  def encode_type(:principal), do: LEB128.encode_signed(-24)
  def encode_type({:opt, type}), do: LEB128.encode_signed(-18) <> encode_type(type)
  def encode_type({:vec, type}), do: LEB128.encode_signed(-19) <> encode_type(type)
  def encode_type(:blob), do: encode_type({:vec, :nat8})

  def decode(term) do
    {value, rest} = LEB128.decode_signed!(term)
    {do_decode(value), rest}
  end

  def do_decode(-1), do: :null
  def do_decode(-2), do: :bool
  def do_decode(-3), do: :nat
  def do_decode(-4), do: :int
  def do_decode(-5), do: :nat8
  def do_decode(-6), do: :nat16
  def do_decode(-7), do: :nat32
  def do_decode(-8), do: :nat64
  def do_decode(-9), do: :int8
  def do_decode(-10), do: :int16
  def do_decode(-11), do: :int32
  def do_decode(-12), do: :int64
  def do_decode(-13), do: :float32
  def do_decode(-14), do: :float64
  def do_decode(-15), do: :text
  def do_decode(-16), do: :reserved
  def do_decode(-17), do: :empty
  def do_decode(-24), do: :principal
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
      value["tree"]
    else
      ret
    end
  end

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
    refbin = decode_textual(reftext)

    IO.inspect(refbin, label: "refbin")
    idsize = byte_size(wallet_id(wallet))
    ^idsize = byte_size(refbin)
    ^refbin = IO.inspect(wallet_id(wallet), label: "wallet_id")
    ^reftext = IO.inspect(wallet_textual(wallet), label: "wallet_textual")

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

    [1] = query(canister_id, w, "get_max_message_id")

    message = "hello world"
    hash = h(message)
    key_id = Wallet.address!(w)
    [1] = call(canister_id, w, "add_message", [:blob, :blob, :blob], [key_id, hash, message])
  end

  def cbor_bytes(data) do
    %CBOR.Tag{tag: :bytes, value: data}
  end

  def decode_textual(canister_id) do
    <<_crc32::binary-size(4), canister_bin_id::binary>> =
      String.replace(canister_id, "-", "") |> Base.decode32!(case: :lower, padding: false)

    canister_bin_id
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
