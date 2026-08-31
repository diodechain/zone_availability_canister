import Base16 "mo:base16/Base16";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Eth "./Eth";
import EthRpc "./EthRpc";
import Map "mo:map/Map";
import Oracle "./Oracle";
import Principal "mo:base/Principal";
import Time "mo:base/Time";

module MemberCache {
  public type Cache = {
    zone_id : Text;
    backend : EthRpc.Backend;
    zone_members : Map.Map<Blob, CacheEntry>;
    transform_function : Oracle.TransformFunction;
    call_token : ?Blob;
  };

  public type CacheEntry = {
    role : Nat;
    identity_contract : ?Blob;
    timestamp : Int;
  };

  public func new(
    zone_id : Text,
    rpc_host : Text,
    rpc_path : Text,
    transform_function : Oracle.TransformFunction,
    call_token : ?Blob,
  ) : Cache {
    new_with_backend(
      zone_id,
      EthRpc.backend_from_legacy_host(rpc_host, rpc_path),
      transform_function,
      call_token,
    );
  };

  public func new_with_backend(
    zone_id : Text,
    backend : EthRpc.Backend,
    transform_function : Oracle.TransformFunction,
    call_token : ?Blob,
  ) : Cache {
    {
      zone_id = zone_id;
      backend = backend;
      transform_function = transform_function;
      zone_members = Map.new();
      call_token = call_token;
    };
  };

  public func rebind(
    cache : Cache,
    zone_id : Text,
    backend : EthRpc.Backend,
  ) : Cache {
    {
      zone_id = zone_id;
      backend = backend;
      transform_function = cache.transform_function;
      zone_members = Map.new();
      call_token = cache.call_token;
    };
  };

  func get_zone_role(cache : Cache, member_address_hex : Text) : async Nat {
    let data = switch (cache.call_token) {
      case (null) {
        Oracle.member_role_calldata(member_address_hex);
      };
      case (?token) {
        if (token.size() != 32) {
          throw Error.reject("Invalid call token size: " # debug_show (token.size()));
        };
        Oracle.member_role_with_token_calldata(token, member_address_hex);
      };
    };
    await EthRpc.eth_call_nat(cache.backend, cache.transform_function, cache.zone_id, data);
  };

  public func update_identity_member(cache : Cache, member_pubkey : Blob, identity_contract : Blob) : async Nat {
    if (identity_contract.size() != 20) {
      throw Error.reject("Invalid identity contract size: " # debug_show (identity_contract.size()));
    };

    if (member_pubkey.size() != 65) {
      throw Error.reject("Invalid public key size: " # debug_show (member_pubkey.size()));
    };

    let member = Eth.principalFromPublicKey(member_pubkey);
    let address = Eth.addressFromPublicKey(member_pubkey);
    let address_hex = Base16.encode(address);

    let identity_contract_hex = Base16.encode(identity_contract);
    let identity_to = "0x" # identity_contract_hex;
    let is_member_nat = await EthRpc.eth_call_nat(
      cache.backend,
      cache.transform_function,
      identity_to,
      Oracle.identity_member_calldata(address_hex),
    );

    if (is_member_nat != 1) {
      throw Error.reject("Member is not in identity");
    };

    let role = await get_zone_role(cache, identity_contract_hex);
    return set_identity_member(cache, member, role, ?identity_contract);
  };

  public func update_member(cache : Cache, member_pubkey : Blob) : async Nat {
    if (member_pubkey.size() != 65) {
      throw Error.reject("Invalid public key size: " # debug_show (member_pubkey.size()));
    };

    let member = Eth.principalFromPublicKey(member_pubkey);
    let address = Eth.addressFromPublicKey(member_pubkey);
    let address_hex = Base16.encode(address);

    let role = await get_zone_role(cache, address_hex);
    return set_identity_member(cache, member, role, null);
  };

  func set_identity_member(cache : Cache, member : Principal, role : Nat, identity_contract : ?Blob) : Nat {
    // This code ensure that identity contract hex is not changed after it is set
    // this ensures that public calls to update_member() are not able to unset the cached proper role
    // by supplying a different identity contract hex
    let key = Principal.toBlob(member);
    switch (Map.get<Blob, CacheEntry>(cache.zone_members, Map.bhash, key)) {
      case (null) {
        Map.set<Blob, CacheEntry>(cache.zone_members, Map.bhash, key, { role = role; timestamp = Time.now(); identity_contract = identity_contract });
      };
      case (?entry) {
        if (entry.identity_contract == identity_contract) {
          Map.set<Blob, CacheEntry>(cache.zone_members, Map.bhash, key, { role = role; timestamp = Time.now(); identity_contract = identity_contract });
        } else {
          Debug.trap("Identity contract hex mismatch");
        };
      };
    };
    return role;
  };

  public func set_member(cache : Cache, member : Principal, role : Nat) : Nat {
    return set_identity_member(cache, member, role, null);
  };

  public func get_member(cache : Cache, member : Principal) : ?CacheEntry {
    let key = Principal.toBlob(member);
    Map.get<Blob, CacheEntry>(cache.zone_members, Map.bhash, key);
  };

  public func get_role(cache : Cache, member : Principal) : Nat {
    switch (get_member(cache, member)) {
      case (null) {
        0;
      };
      case (?member) {
        member.role;
      };
    };
  };

  public func is_member(cache : Cache, member : Principal) : Bool {
    get_role(cache, member) > 0;
  };
};
