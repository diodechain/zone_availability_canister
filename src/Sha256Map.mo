import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import Region "mo:base/Region";

module {
  public type Map = {
    region : Region;
    offset : Nat64;
    depth: Nat;
    key_size : Nat;
    value_size : Nat;
    parent : ?Map;
  };

  public func new(key_size: Nat, value_size: Nat) : Map {
    return {
      region = Region.new();
      offset = 0;
      depth = 0;
      key_size = key_size;
      value_size = value_size;
      parent = null;
    };
  };

  public func capacity(map: Map) : Nat {
    return Nat64.toNat(Region.size(map.region)) / element_size(map);
  };

  public func element_size(map: Map) : Nat {
    return map.key_size + map.value_size;
  };

  private func index(map: Map, key: Blob) : Nat {
    return Nat32.toNat(Blob.hash(key)) % capacity(map);
  };

  public func put(map: Map, key: Blob, value: Blob) {
    if (key.size() != map.key_size) {
      Debug.print("Key size mismatch");
      return;
    };
    if (value.size() != map.value_size) {
      Debug.print("Value size mismatch");
      return;
    };
    let slot = index(map, key);
    do_set(map, slot, key, value);
  };

  private func do_set(map: Map, slot: Nat, key: Blob, value: Blob) {
    let (mark, key2, _value2) = get_slot(map, slot);
    if (mark == 0 or key2 == key) {
      set_slot(map, slot, key, value);
    } else {
      do_set(map, slot + 1, key, value);
    };
  };
  
  public func get(map: Map, key: Blob) : ?Blob {
    let slot = index(map, key);
    return do_get(map, key, slot);
  };

  private func do_get(map: Map, key: Blob, slot: Nat) : ?Blob {
    let (mark, key2, value2) = get_slot(map, slot);

    if (mark == 0) {
        switch (map.parent) {
            case (null) { return null; };
            case (?parent) { return get(parent, key); };
        };
    };

    if (key2 == key) {
        return ?value2;
    };

    return do_get(map, key, slot + 1);
  };

  private func get_slot(map: Map, slot: Nat) : (Nat8, Blob, Blob) {
    let offset = Nat64.fromNat(slot * element_size(map)); 
    (
        Region.loadNat8(map.region, offset),
        Region.loadBlob(map.region, offset + 1, map.key_size),
        Region.loadBlob(map.region, offset + 1 + Nat64.fromNat(map.key_size), map.value_size)
    );
  };

  private func set_slot(map: Map, slot: Nat, key: Blob, value: Blob) {
    let offset = Nat64.fromNat(slot * element_size(map)); 
    Region.storeNat8(map.region, offset, 1);
    Region.storeBlob(map.region, offset + 1, key);
    Region.storeBlob(map.region, offset + 1 + Nat64.fromNat(map.key_size), value);
  };
}