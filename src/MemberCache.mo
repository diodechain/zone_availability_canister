import Map "mo:map/Map";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Eth "./Eth";
import Oracle "./Oracle";
import Time "mo:base/Time";
import Base16 "mo:base16/Base16";
import Debug "mo:base/Debug";

module MemberCache {
    public type Cache = {
        zone_id : Text;
        rpc_host : Text;
        rpc_path : Text;
        zone_members : Map.Map<Blob, CacheEntry>;
    };

    public type CacheEntry = {
        role : Nat;
        identity_contract : ?Blob;
        timestamp : Int;
    };

    public func new(zone_id : Text, rpc_host : Text, rpc_path : Text) : Cache {
        {
            zone_id = zone_id;
            rpc_host = rpc_host;
            rpc_path = rpc_path;
            zone_members = Map.new();
        };
    };

    public func update_identity_member(cache : Cache, member_pubkey : Blob, identity_contract : Blob) : async Nat {
        if (identity_contract.size() != 20) {
            Debug.trap("Invalid identity contract size: " # debug_show (identity_contract.size()));
        };

        if (member_pubkey.size() != 65) {
            Debug.trap("Invalid public key size: " # debug_show (member_pubkey.size()));
        };

        let member = Eth.principalFromPublicKey(member_pubkey);
        let address = Eth.addressFromPublicKey(member_pubkey);
        let address_hex = Base16.encode(address);

        let identity_contract_hex = Base16.encode(identity_contract);
        let is_member = await Oracle.is_identity_member("0x" # identity_contract_hex, address_hex, cache.rpc_host, cache.rpc_path);

        if (not is_member) {
            Debug.trap("Member is not in identity");
        };

        let role = await Oracle.get_zone_member_role(cache.zone_id, identity_contract_hex, cache.rpc_host, cache.rpc_path);
        return set_identity_member(cache, member, role, ?identity_contract);
    };

    public func update_member(cache : Cache, member_pubkey : Blob) : async Nat {
        if (member_pubkey.size() != 65) {
            Debug.trap("Invalid public key size: " # debug_show (member_pubkey.size()));
        };

        let member = Eth.principalFromPublicKey(member_pubkey);
        let address = Eth.addressFromPublicKey(member_pubkey);
        let address_hex = Base16.encode(address);

        let role = await Oracle.get_zone_member_role(cache.zone_id, address_hex, cache.rpc_host, cache.rpc_path);
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
