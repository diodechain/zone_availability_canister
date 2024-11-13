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

    public func update_member(cache : Cache, member : Principal) : async () {
        Debug.print(debug_show("Fetching eth address for member " # Principal.toText(member)));
        switch (await Eth.addressFromPrincipal(member)) {
            case (null) {
                return;
            };
            case (?address) {
                let address_hex = Base16.encode(address);
                Debug.print(debug_show(address_hex));
                let role = await Oracle.get_zone_member_role(cache.zone_id, address_hex, cache.rpc_host, cache.rpc_path);
                Debug.print(debug_show(role));
                let key = Principal.toBlob(member);
                Map.set<Blob, CacheEntry>(cache.zone_members, Map.bhash, key, { role = role; timestamp = Time.now() });
                return;
            };
        };
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
