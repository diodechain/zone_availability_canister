import { abs } = "mo:base/Int";
import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";

module DiodeMessages {
  public type Message = {
    id: Nat32;
    timestamp: Nat32;
    key_id: Blob;
    hash: Blob;
    ciphertext: Blob;
  };

  let inbox_entry_size : Nat64 = 76;
  let key_inbox_entry_size : Nat64 = 8;

  public type MessageStore = {
    var inbox: WriteableBand.WriteableBand;
    var inbox_index: Nat32;
    var payloads: WriteableBand.WriteableBand;
    var key_inbox: Map.Map<Blob, WriteableBand.WriteableBand>;
    var message_index: Map.Map<Blob, Nat32>;
  };

  public func new() : MessageStore {
    return {
      var inbox = WriteableBand.new();
      var inbox_index = 0;
      var payloads = WriteableBand.new();
      var key_inbox = Map.new<Blob, WriteableBand.WriteableBand>();
      var message_index = Map.new<Blob, Nat32>();
    };
  };


  public func add_message(store: MessageStore, key_id: Blob, hash: Blob, ciphertext: Blob) : Result.Result<(), Text> {
    if (key_id.size() != 24) {
      return #err("key_id must be 24 bytes");
    };

    if (Map.has<Blob, Nat32>(store.message_index, Map.bhash, hash)) {
      return #ok;
    };

    if (hash.size() != 32) {
      return #err("hash must be 32 bytes");
    };

    // START: Insert cipertext into payloads
    let before_offset = store.payloads.end;
    WriteableBand.appendBlob(store.payloads, ciphertext);
    // END: Insert cipertext into payloads

    // START: Insert message into inbox
    Map.set<Blob, Nat32>(store.message_index, Map.bhash, hash, store.inbox_index);

    let timestamp : Nat32 = Nat32.fromNat(abs(now()) / 1_000_000_000);
    let inbox_before = store.inbox.end;
    WriteableBand.appendNat32(store.inbox, store.inbox_index);
    WriteableBand.appendNat32(store.inbox, timestamp);
    WriteableBand.appendBlob(store.inbox, key_id);
    WriteableBand.appendBlob(store.inbox, hash);
    WriteableBand.appendNat64(store.inbox, before_offset);
    WriteableBand.appendNat32(store.inbox, Nat32.fromNat(ciphertext.size()));
    
    if (store.inbox.end != inbox_before + inbox_entry_size) {
      return #err("Inbox end is not equal to inbox before + inbox entry size");
    };
    // END: Insert message into inbox

    // START: Insert message reference into key_inbox
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(store.key_inbox, Map.bhash, key_id);
    let key_inbox_band = switch (ret) {
      case (null) { WriteableBand.new() };
      case (?value) { value };
    };

    let key_inbox_band_before = key_inbox_band.end;
    WriteableBand.appendNat32(key_inbox_band, store.inbox_index);
    WriteableBand.appendNat32(key_inbox_band, timestamp);
    if (key_inbox_band.end != key_inbox_band_before + key_inbox_entry_size) {
      return #err("Key inbox band end is not equal to key inbox band before + key inbox band entry size");
    };
    Map.set<Blob, WriteableBand.WriteableBand>(store.key_inbox, Map.bhash, key_id, key_inbox_band);
    // END: Insert message reference into key_inbox

    store.inbox_index += 1;
    return #ok;
  };

  private func get_message_offset_by_hash(store: MessageStore, message_hash: Blob) : ?Nat64 {
    let index = Map.get<Blob, Nat32>(store.message_index, Map.bhash, message_hash);
    return switch (index) {
      case (null) { null };
      case (?id) { ?get_message_offset_by_id(store, id) };
    };
  };

  private func get_message_offset_by_id(_store: MessageStore, message_id: Nat32) : Nat64 {
    return Nat64.fromNat32(message_id) * inbox_entry_size;
  };

  public func get_message_by_hash(store: MessageStore, message_hash: Blob) : ?Message {
    return switch (get_message_offset_by_hash(store, message_hash)) {
      case (null) { null };
      case (?offset) { ?get_message_by_offset(store, offset) };
    };
  };

  public func get_message_by_id(store: MessageStore, message_id: Nat32) : Message {
    let offset = get_message_offset_by_id(store, message_id);
    return get_message_by_offset(store, offset);
  };

  private func get_message_by_offset(store: MessageStore, offset: Nat64) : Message {
    let id = Region.loadNat32(store.inbox.region, offset);
    let timestamp = Region.loadNat32(store.inbox.region, offset + 4);
    let key_id = Region.loadBlob(store.inbox.region, offset + 8, 24);
    let hash = Region.loadBlob(store.inbox.region, offset + 32, 32);
    let payload_offset = Region.loadNat64(store.inbox.region, offset + 64);
    let payload_size = Region.loadNat32(store.inbox.region, offset + 72);
    let ciphertext = Region.loadBlob(store.payloads.region, payload_offset, Nat32.toNat(payload_size));

    return {
      id = id;
      timestamp = timestamp;
      key_id = key_id;
      hash = hash;
      ciphertext = ciphertext;
    };
  };

  public func get_min_message_id(_store: MessageStore) : Nat32 {
    return 0;
  };

  public func get_max_message_id(store: MessageStore) : Nat32 {
    return store.inbox_index;
  };

  public func get_min_message_id_by_key(store: MessageStore, key_id: Blob) : ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(store.key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) { ?Region.loadNat32(value.region, 0); };
    };
  };

  public func get_max_message_id_by_key(store: MessageStore, key_id: Blob) : ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(store.key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) { ?Region.loadNat32(value.region, value.end - key_inbox_entry_size); };
    };
  };

  public func get_idx_message_id_by_key(store: MessageStore, key_id: Blob, idx: Nat32) : ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(store.key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) {
        let offset = Nat64.fromNat32(idx) * key_inbox_entry_size;
        if (offset + key_inbox_entry_size > value.end) {
          null;
        } else {
          ?Region.loadNat32(value.region, offset);
        };
      };
    };
  };
};
