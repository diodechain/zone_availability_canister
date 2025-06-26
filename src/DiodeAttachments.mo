import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";

module DiodeAttachments {
  /*
    AttachmentStore is a writeable ring-buffer of attachments. When the size limit is reached, the ring-buffer is
    starting to overwrite the oldest attachment.

    To create a new attachment there are two variants for small and large attachments respectively:
    - small attachments can be created and written in one function call using write_attachment()
    - large attachments are stored in three phases:
        - allocate_attachment()
        - n times write_attachment_chunk()
        - finalize_attachment()

    After the attachment is finalized, it can be read using read_attachment() and read_attachment_chunk().
    Small attachments are finalized immediately after calling write_attachment()
    */

  public type Attachment = {
    identity_hash : Blob;
    timestamp : Nat32;
    finalized : Bool;
    ciphertext : Blob;
  };

  let metadata_size : Nat64 = 48; // 32 + 4 + 4 + 8; // identity_hash + timestamp + finalized(nat32) + size(nat64)

  public type AttachmentMetadata = {
    identity_hash : Blob;
    timestamp : Nat32;
    finalized : Bool;
    size : Nat64;
  };

  public type AttachmentStore = {
    var attachments : WriteableBand.WriteableBand;
    var first_entry_offset : Nat64;
    var end_offset : Nat64;
    var max_offset : Nat64;
    var next_entry_offset : ?Nat64;
    var hash_to_offset : Map.Map<Blob, Nat64>;
  };

  public func new(max_offset : Nat64) : AttachmentStore {
    return {
      var attachments = WriteableBand.new();
      var first_entry_offset = 0;
      var end_offset = 0;
      var max_offset = max_offset;
      var next_entry_offset = null;
      var hash_to_offset = Map.new<Blob, Nat64>();
    };
  };

  public func set_max_offset(store : AttachmentStore, max_offset : Nat64) {
    store.max_offset := max_offset;
  };

  public func write_attachment(store : AttachmentStore, identity_hash : Blob, data : Blob) : Result.Result<(), Text> {
    switch (allocate_attachment(store, identity_hash, Nat64.fromNat(data.size()))) {
      case (#err(err)) {
        return #err(err);
      };
      case (#ok(_offset)) {
        switch (write_attachment_chunk(store, identity_hash, 0, data.size(), data)) {
          case (#err(err)) {
            delete_attachment(store, identity_hash);
            return #err(err);
          };
          case (#ok()) {
            switch (finalize_attachment(store, identity_hash)) {
              case (#err(err)) {
                delete_attachment(store, identity_hash);
                return #err(err);
              };
              case (#ok()) {
                return #ok();
              };
            };
          };
        };
      };
    };
  };

  public func allocate_attachment(store : AttachmentStore, identity_hash : Blob, size : Nat64) : Result.Result<Nat64, Text> {
    if (size == 0) {
      return #err("size must be greater than 0");
    };

    if (identity_hash.size() != 32) {
      return #err("identity_hash must be 32 bytes");
    };

    if (metadata_size + size > store.max_offset) {
      return #err("size is too large");
    };

    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        // passthrough
      };
      case (?value) {
        return #ok(value);
      };
    };

    // Entry will not fit in the current space, wrap around to the beginning of the band
    if (store.end_offset + size + metadata_size > store.max_offset) {
      store.end_offset := 0;
      store.next_entry_offset := ?0;
    };

    let end = store.end_offset + size + metadata_size;
    let _ = do ? {
      while (store.next_entry_offset! < end) {
        remove_next_entry(store);
      };
    };

    let offset = store.end_offset;
    WriteableBand.writeBlob(store.attachments, offset, identity_hash);
    WriteableBand.appendNat32(store.attachments, Nat32.fromIntWrap(now()));
    WriteableBand.appendNat32(store.attachments, 0); // 0 means not finalized
    WriteableBand.appendNat64(store.attachments, size);
    // We're writing 0 to the timestamp of the next entry to mark it as empty
    WriteableBand.writeNat32(store.attachments, offset + metadata_size + size + 32, 0);
    store.end_offset += size + metadata_size;
    Map.set<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash, offset);
    return #ok(offset);
  };

  public func delete_attachment(store : AttachmentStore, identity_hash : Blob) {
    Map.delete<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash);
  };

  public func get_attachment(store : AttachmentStore, identity_hash : Blob) : Result.Result<Attachment, Text> {
    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        return #err("attachment not found");
      };
      case (?offset) {
        let meta_data = _read_metadata(store, offset);
        let ciphertext = WriteableBand.readBlob(store.attachments, offset + metadata_size, Nat64.toNat(meta_data.size));
        return #ok({
          identity_hash = identity_hash;
          timestamp = meta_data.timestamp;
          finalized = meta_data.finalized;
          ciphertext = ciphertext;
        });
      };
    };
  };

  public func get_attachment_metadata(store : AttachmentStore, identity_hash : Blob) : Result.Result<AttachmentMetadata, Text> {
    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        return #err("attachment not found");
      };
      case (?offset) {
        return #ok(_read_metadata(store, offset));
      };
    };
  };

  private func _read_metadata(store : AttachmentStore, offset : Nat64) : AttachmentMetadata {
    let identity_hash = WriteableBand.readBlob(store.attachments, offset, 32);
    let timestamp = WriteableBand.readNat32(store.attachments, offset + 32);
    let finalized = WriteableBand.readNat32(store.attachments, offset + 32 + 4) == 1;
    let size = WriteableBand.readNat64(store.attachments, offset + 32 + 4 + 4);
    return {
      identity_hash = identity_hash;
      timestamp = timestamp;
      finalized = finalized;
      size = size;
    };
  };

  public func read_attachment_chunk(store : AttachmentStore, identity_hash : Blob, chunk_offset : Nat64, chunk_size : Nat) : Result.Result<Blob, Text> {
    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        return #err("attachment not found");
      };
      case (?offset) {
        let meta_data = _read_metadata(store, offset);
        if (chunk_offset + Nat64.fromNat(chunk_size) > meta_data.size) {
          return #err("chunk out of bounds");
        };
        if (not meta_data.finalized) {
          return #err("attachment is not finalized");
        };

        let chunk = WriteableBand.readBlob(store.attachments, offset + metadata_size + chunk_offset, chunk_size);
        return #ok(chunk);
      };
    };
  };

  public func write_attachment_chunk(store : AttachmentStore, identity_hash : Blob, chunk_offset : Nat64, chunk_size : Nat, chunk : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        return #err("attachment not found");
      };
      case (?offset) {
        let meta_data = _read_metadata(store, offset);
        if (chunk_offset + Nat64.fromNat(chunk_size) > meta_data.size) {
          return #err("chunk out of bounds");
        };
        if (meta_data.finalized) {
          return #err("attachment is finalized");
        };
        WriteableBand.writeBlob(store.attachments, offset + metadata_size + chunk_offset, chunk);
        return #ok();
      };
    };
  };

  public func finalize_attachment(store : AttachmentStore, identity_hash : Blob) : Result.Result<(), Text> {
    switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
      case (null) {
        return #err("attachment not found");
      };
      case (?offset) {
        WriteableBand.writeNat32(store.attachments, offset + 32 + 4, 1);
        return #ok();
      };
    };
  };

  func remove_next_entry(store : AttachmentStore) {
    switch (store.next_entry_offset) {
      case (null) {
        return;
      };
      case (?offset) {
        let meta_data = _read_metadata(store, offset);
        WriteableBand.writeNat32(store.attachments, offset + 32, 0);
        delete_attachment(store, meta_data.identity_hash);
        var next_entry_offset = offset + metadata_size + meta_data.size;
        // Wrap around to the beginning of the band
        let max_size = Nat64.min(store.max_offset, WriteableBand.capacity(store.attachments));
        if (next_entry_offset + metadata_size + 1 > max_size) {
          store.next_entry_offset := null;
          return;
        };

        // This might be the beginning of the band (0) or the next entry somewhere in the middle
        let next_meta_data = _read_metadata(store, next_entry_offset);
        if (next_meta_data.timestamp == 0) {
          store.next_entry_offset := null;
          return;
        };

        store.next_entry_offset := ?next_entry_offset;
      };
    };
  };
};
