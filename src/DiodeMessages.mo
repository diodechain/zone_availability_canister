import { abs } = "mo:base/Int";
import Iter "mo:base/Iter";
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
    next_msg_id: Nat32;
    prev_msg_id: Nat32;
    hash: Blob;
    ciphertext: Blob;
  };

  let inbox_entry_size : Nat64 = 84;


  type KeyInboxEntry = {
    var min_msg_id: Nat32;
    var max_msg_id: Nat32;
    var message_count: Nat32;
  };

  public type MessageStore = {
    var inbox: WriteableBand.WriteableBand;
    var inbox_index: Nat32;
    var payloads: WriteableBand.WriteableBand;
    var key_inbox: Map.Map<Blob, KeyInboxEntry>;
    var message_index: Map.Map<Blob, Nat32>;
  };

  public func new() : MessageStore {
    return {
      var inbox = WriteableBand.new();
      var inbox_index = 1;
      var payloads = WriteableBand.new();
      var key_inbox = Map.new<Blob, KeyInboxEntry>();
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

    // START: Insert message reference into key_inbox
    let prev_entry = Map.get<Blob, KeyInboxEntry>(store.key_inbox, Map.bhash, key_id);
    let new_entry : KeyInboxEntry = switch(prev_entry) {
      case (null) {
        {
          var min_msg_id = store.inbox_index;
          var max_msg_id = store.inbox_index;
          var message_count = 1;
        };
      };
      case (?value) { 
        {
          var min_msg_id = value.min_msg_id;
          var max_msg_id = store.inbox_index;
          var message_count = value.message_count + 1;
        };
      };
    };

    Map.set<Blob, KeyInboxEntry>(store.key_inbox, Map.bhash, key_id, new_entry);
    // END: Insert message reference into key_inbox

    // START: Insert message into inbox
    Map.set<Blob, Nat32>(store.message_index, Map.bhash, hash, store.inbox_index);

    let timestamp : Nat32 = Nat32.fromNat(abs(now()) / 1_000_000_000);
    let inbox_before = store.inbox.end;
    WriteableBand.appendNat32(store.inbox, store.inbox_index);
    WriteableBand.appendNat32(store.inbox, timestamp);
    WriteableBand.appendBlob(store.inbox, key_id);
    WriteableBand.appendNat32(store.inbox, 0); // next_msg_id is always 0 for a new message
    WriteableBand.appendNat32(store.inbox, switch (prev_entry) {
      case (null) { 0 };
      case (?value) { value.max_msg_id };
    });
    WriteableBand.appendBlob(store.inbox, hash);
    WriteableBand.appendNat64(store.inbox, before_offset);
    WriteableBand.appendNat32(store.inbox, Nat32.fromNat(ciphertext.size()));
    if (store.inbox.end != inbox_before + inbox_entry_size) {
      return #err("Inbox end is not equal to inbox before + inbox entry size");
    };

    // Update the next_msg_id of the previous message
    switch (prev_entry) {
      case (null) { };
      case (?value) {
        let prev_msg_offset = get_message_offset_by_id(store, value.max_msg_id);
        Region.storeNat32(store.inbox.region, prev_msg_offset + 32, store.inbox_index);
      };
    };

    // END: Insert message into inbox

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
    assert(message_id > 0);
    return Nat64.fromNat32(message_id - 1) * inbox_entry_size;
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
    let next_msg_id = Region.loadNat32(store.inbox.region, offset + 32);
    let prev_msg_id = Region.loadNat32(store.inbox.region, offset + 36);
    let hash = Region.loadBlob(store.inbox.region, offset + 40, 32);
    let payload_offset = Region.loadNat64(store.inbox.region, offset + 72);
    let payload_size = Region.loadNat32(store.inbox.region, offset + 80);
    let ciphertext = Region.loadBlob(store.payloads.region, payload_offset, Nat32.toNat(payload_size));

    return {
      id = id;
      timestamp = timestamp;
      key_id = key_id;
      next_msg_id = next_msg_id;
      prev_msg_id = prev_msg_id;
      hash = hash;
      ciphertext = ciphertext;
    };
  };

  public func get_min_message_id(store: MessageStore) : Nat32 {
    if (store.inbox_index == 1) {
      return 0;
    };
    return 1;
  };

  public func get_max_message_id(store: MessageStore) : Nat32 {
    return store.inbox_index;
  };

  public func get_min_message_id_by_key(store: MessageStore, key_id: Blob) : ?Nat32 {
    return switch (Map.get<Blob, KeyInboxEntry>(store.key_inbox, Map.bhash, key_id)) {
      case (null) { null; };
      case (?value) { ?value.min_msg_id };
    };
  };

  public func get_max_message_id_by_key(store: MessageStore, key_id: Blob) : ?Nat32 {
    return switch (Map.get<Blob, KeyInboxEntry>(store.key_inbox, Map.bhash, key_id)) {
      case (null) { null; };
      case (?value) { ?value.max_msg_id };
    };
  };
};
