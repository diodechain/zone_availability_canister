import Array "mo:base/Array";
import Base16 "mo:base16/Base16";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Oracle "./Oracle";

module EthRpc {
  public type Network = {
    #BaseMainnet;
  };

  public type Backend = {
    #HttpOutcall : { host : Text; path : Text };
    #ChainFusion : { network : Network };
  };

  public let BASE_RPC_HOST : Text = "mainnet.base.org";
  public let MOONBEAM_RPC_HOST : Text = "rpc.api.moonbeam.network";
  public let EVM_RPC_CANISTER_ID : Text = "7hfb6-caaaa-aaaar-qadga-cai";
  public let ETH_CALL_CYCLES : Nat = 10_000_000_000;
  public let MAX_RESPONSE_BYTES : Nat64 = 1024;

  public type L2MainnetService = {
    #Alchemy;
    #Ankr;
    #BlockPi;
    #PublicNode;
    #Llama;
  };

  public type RpcService = {
    #BaseMainnet : L2MainnetService;
  };

  public type RpcError = {
    #JsonRpcError : { code : Int64; message : Text };
    #ProviderError : {
      #TooFewCycles : { expected : Nat; received : Nat };
      #MissingRequiredProvider;
      #ProviderNotFound;
      #NoPermission;
      #InvalidRpcConfig : Text;
    };
    #ValidationError : { #Custom : Text; #InvalidHex : Text };
    #HttpOutcallError : {
      #IcError : {
        code : {
          #NoError;
          #CanisterError;
          #SysTransient;
          #DestinationInvalid;
          #Unknown;
          #SysFatal;
          #CanisterReject;
        };
        message : Text;
      };
      #InvalidHttpJsonRpcResponse : {
        status : Nat16;
        body : Text;
        parsingError : ?Text;
      };
    };
  };

  public type RequestResult = {
    #Ok : Text;
    #Err : RpcError;
  };

  public type EvmRpcActor = actor {
    request : (RpcService, Text, Nat64) -> async RequestResult;
  };

  public func backend_from_legacy_host(host : Text, path : Text) : Backend {
    if (host == BASE_RPC_HOST) {
      #ChainFusion({ network = #BaseMainnet });
    } else {
      #HttpOutcall({ host = host; path = path });
    };
  };

  public func backend_to_text(backend : Backend) : Text {
    switch (backend) {
      case (#HttpOutcall({ host; path })) {
        "http:" # host # path;
      };
      case (#ChainFusion({ network = #BaseMainnet })) {
        "chain-fusion:base";
      };
    };
  };

  func ensure_0x_address(to : Text) : Text {
    if (Text.startsWith(to, #text "0x") or Text.startsWith(to, #text "0X")) {
      to;
    } else {
      "0x" # to;
    };
  };

  func ensure_0x_data(data : Text) : Text {
    if (Text.startsWith(data, #text "0x") or Text.startsWith(data, #text "0X")) {
      data;
    } else {
      "0x" # data;
    };
  };

  func blob_to_nat(blob : Blob) : Nat {
    let array = Blob.toArray(blob);
    Array.foldLeft<Nat8, Nat>(array, 0, func(acc, byte) { acc * 256 + Nat8.toNat(byte) });
  };

  func json_result_to_blob(json : Text) : ?Blob {
    switch (Text.encodeUtf8(json)) {
      case (blob) {
        Oracle.process_http_response({
          status = 200;
          headers = [];
          body = Blob.toArray(blob);
        });
      };
    };
  };

  public func eth_call(
    backend : Backend,
    transform_function : Oracle.TransformFunction,
    to : Text,
    data : Text,
  ) : async ?Blob {
    switch (backend) {
      case (#HttpOutcall({ host; path })) {
        let context : Oracle.Context = {
          rpc_host = host;
          rpc_path = path;
          transform_function = transform_function;
        };
        let request = Oracle.create_eth_call_request(context, to, data);
        let response = await (with cycles = 20_949_972_000) Oracle.http_actor().http_request(request);
        Oracle.process_http_response(response);
      };
      case (#ChainFusion({ network = #BaseMainnet })) {
        let evm : EvmRpcActor = actor (EVM_RPC_CANISTER_ID);
        let to_addr = ensure_0x_address(to);
        let input = ensure_0x_data(data);
        if (to_addr.size() != 42) {
          Debug.trap("Invalid 'to' address size: " # debug_show (to_addr.size()));
        };
        let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"" # to_addr # "\",\"data\":\"" # input # "\"},\"latest\"]}";
        let result = await (with cycles = ETH_CALL_CYCLES) evm.request(
          #BaseMainnet(#PublicNode),
          json,
          MAX_RESPONSE_BYTES,
        );
        switch (result) {
          case (#Ok(response_json)) { json_result_to_blob(response_json) };
          case (#Err(err)) {
            Debug.print("eth_call ChainFusion error: " # debug_show (err));
            null;
          };
        };
      };
    };
  };

  public func eth_call_nat(
    backend : Backend,
    transform_function : Oracle.TransformFunction,
    to : Text,
    data : Text,
  ) : async Nat {
    switch (await eth_call(backend, transform_function, to, data)) {
      case (null) { 0 };
      case (?blob) { blob_to_nat(blob) };
    };
  };
};
