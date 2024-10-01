import { abs } = "mo:base/Int";
import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";

actor class DiodeMessages() {
  type Message = {
    id: Nat32;
    timestamp: Nat32;
    key_id: Blob;
    hash: Blob;
    ciphertext: Blob;
  };

  let inbox_entry_size : Nat64 = 76;
  let key_inbox_entry_size : Nat64 = 8;

  stable var inbox = WriteableBand.new();
  stable var inbox_index : Nat32 = 0;
  stable var payloads = WriteableBand.new();
  stable var key_inbox = Map.new<Blob, WriteableBand.WriteableBand>();
  stable var message_index = Map.new<Blob, Nat32>();

  public func add_message(key_id: Blob, hash: Blob, ciphertext: Blob) : async Result.Result<(), Text> {
    if (key_id.size() != 24) {
      return #err("key_id must be 24 bytes");
    };

    if (Map.has<Blob, Nat32>(message_index, Map.bhash, hash)) {
      return #ok;
    };

    if (hash.size() != 32) {
      return #err("hash must be 32 bytes");
    };

    // START: Insert cipertext into payloads
    let before_offset = payloads.end;
    WriteableBand.appendBlob(payloads, ciphertext);
    // END: Insert cipertext into payloads

    // START: Insert message into inbox
    Map.set<Blob, Nat32>(message_index, Map.bhash, hash, inbox_index);

    let timestamp : Nat32 = Nat32.fromNat(abs(now()) / 1_000_000);
    let inbox_before = inbox.end;
    WriteableBand.appendNat32(inbox, inbox_index);
    WriteableBand.appendNat32(inbox, timestamp);
    WriteableBand.appendBlob(inbox, key_id);
    WriteableBand.appendBlob(inbox, hash);
    WriteableBand.appendNat64(inbox, before_offset);
    WriteableBand.appendNat32(inbox, Nat32.fromNat(ciphertext.size()));
    assert (inbox.end == inbox_before + inbox_entry_size);
    // END: Insert message into inbox

    // START: Insert message reference into key_inbox
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(key_inbox, Map.bhash, key_id);
    let key_inbox_band = switch (ret) {
      case (null) { WriteableBand.new() };
      case (?value) { value };
    };

    let key_inbox_band_before = key_inbox_band.end;
    WriteableBand.appendNat32(key_inbox_band, inbox_index);
    WriteableBand.appendNat32(key_inbox_band, timestamp);
    assert (key_inbox_band.end == key_inbox_band_before + key_inbox_entry_size);
    Map.set<Blob, WriteableBand.WriteableBand>(key_inbox, Map.bhash, key_id, key_inbox_band);
    // END: Insert message reference into key_inbox

    inbox_index += 1;
    return #ok;
  };

  private func get_message_offset_by_hash(message_hash: Blob) : ?Nat64 {
    let index = Map.get<Blob, Nat32>(message_index, Map.bhash, message_hash);
    return switch (index) {
      case (null) { null };
      case (?id) { ?get_message_offset_by_id(id) };
    };
  };

  private func get_message_offset_by_id(message_id: Nat32) : Nat64 {
    return Nat64.fromNat32(message_id) * inbox_entry_size;
  };

  public func get_message_by_hash(message_hash: Blob) : async ?Message {
    return switch (get_message_offset_by_hash(message_hash)) {
      case (null) { null };
      case (?offset) { ?get_message_by_offset(offset) };
    };
  };

  public func get_message_by_id(message_id: Nat32) : async Message {
    let offset = get_message_offset_by_id(message_id);
    return get_message_by_offset(offset);
  };

  private func get_message_by_offset(offset: Nat64) : Message {
    let id = Region.loadNat32(inbox.region, offset);
    let timestamp = Region.loadNat32(inbox.region, offset + 4);
    let key_id = Region.loadBlob(inbox.region, offset + 8, 24);
    let hash = Region.loadBlob(inbox.region, offset + 32, 32);
    let payload_offset = Region.loadNat64(inbox.region, offset + 64);
    let payload_size = Region.loadNat32(inbox.region, offset + 72);
    let ciphertext = Region.loadBlob(payloads.region, payload_offset, Nat32.toNat(payload_size));

    return {
      id = id;
      timestamp = timestamp;
      key_id = key_id;
      hash = hash;
      ciphertext = ciphertext;
    };
  };

  public func get_min_message_id() : async Nat32 {
    return 0;
  };

  public func get_max_message_id() : async Nat32 {
    return inbox_index;
  };

  public func get_min_message_id_by_key(key_id: Blob) : async ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) { ?Region.loadNat32(value.region, 0); };
    };
  };

  public func get_max_message_id_by_key(key_id: Blob) : async ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) { ?Region.loadNat32(value.region, value.end - key_inbox_entry_size); };
    };
  };

  public func get_idx_message_id_by_key(key_id: Blob, idx: Nat32) : async ?Nat32 {
    let ret = Map.get<Blob, WriteableBand.WriteableBand>(key_inbox, Map.bhash, key_id);
    return switch (ret) {
      case (null) { null; };
      case (?value) {
        let offset = Nat64.fromNat32(idx) * key_inbox_entry_size;
        if (offset > value.end) {
          null;
        } else {
          ?Region.loadNat32(value.region, offset);
        };
      };
    };
  };
};
