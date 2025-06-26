import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import VetKD "VetKD";

module MetaData {
  public type DataEntry = {
    timestamp : Int;
    data : Blob;
  };

  public type MetaData = {
    var public_key : ?Blob;
    var vet_protected_key : ?Blob;
    var manifest : Nat;
    var timestamp : Int;
    storage : [var ?DataEntry];
  };

  public type MetaDataInfo = {
    public_key : ?Blob;
    vet_protected_key : ?Blob;
    manifest : Nat;
    timestamp : Int;
  };

  public func new() : MetaData {
    {
      var public_key = null;
      var vet_protected_key = null;
      var manifest = 0;
      var timestamp = 0;
      storage = Array.init<?DataEntry>(256, null);
    };
  };

  public func derive_vet_protector_key(_meta_data : MetaData, transport_public_key : Blob, target_public_key : Blob) : async ?Blob {
    let result = await (with cycles = 26_153_846_153) VetKD.system_api.vetkd_derive_key({
      input = "meta_data_encrpytion_key";
      context = target_public_key;
      transport_public_key = transport_public_key;
      key_id = { curve = #bls12_381_g2; name = "key_1" };
    });
    ?result.encrypted_key;
  };

  public func set_public_and_protected_key(meta_data : MetaData, public_key : Blob, vet_protected_key : Blob) {
    meta_data.public_key := ?public_key;
    meta_data.vet_protected_key := ?vet_protected_key;
    meta_data.manifest := 0;
    meta_data.timestamp := 0;
    for (i in meta_data.storage.keys()) {
      meta_data.storage[i] := null;
    };
  };

  public func get_meta_data_info(meta_data : MetaData) : MetaDataInfo {
    {
      public_key = meta_data.public_key;
      vet_protected_key = meta_data.vet_protected_key;
      manifest = meta_data.manifest;
      timestamp = meta_data.timestamp;
    };
  };

  public type DirectoryEntry = {
    key : Nat8;
    timestamp : Int;
  };

  public func get_timestamps(meta_data : MetaData) : [DirectoryEntry] {
    var entries : [DirectoryEntry] = [];

    for (i in meta_data.storage.keys()) {
      switch (meta_data.storage[i]) {
        case (null) {};
        case (?data_entry) {
          entries := Array.append<DirectoryEntry>(entries, [{ key = Nat8.fromIntWrap(i); timestamp = data_entry.timestamp }]);
        };
      };
    };

    entries;
  };

  public func get_data_entry(meta_data : MetaData, key : Nat8) : ?DataEntry {
    meta_data.storage[Nat8.toNat(key)];
  };

  public func set_data_entry(meta_data : MetaData, key : Nat8, data : Blob) {
    let data_entry = {
      timestamp = Time.now();
      data = data;
    };
    meta_data.timestamp := data_entry.timestamp;
    let key_mask = Nat.bitshiftLeft(1, Nat32.fromNat(Nat8.toNat(key)));
    let bit = Nat.bitshiftRight(meta_data.manifest, Nat32.fromNat(Nat8.toNat(key))) % 2;
    if (bit == 0) {
      meta_data.manifest := meta_data.manifest + key_mask;
    };
    meta_data.storage[Nat8.toNat(key)] := ?data_entry;
  };

  public func delete_data_entry(meta_data : MetaData, key : Nat8) {
    meta_data.storage[Nat8.toNat(key)] := null;
    let key_mask = Nat.bitshiftLeft(1, Nat32.fromNat(Nat8.toNat(key)));
    let bit = Nat.bitshiftRight(meta_data.manifest, Nat32.fromNat(Nat8.toNat(key))) % 2;
    if (bit == 1) {
      meta_data.manifest := meta_data.manifest - key_mask;
    };
  };
};
