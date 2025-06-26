import Result "mo:base/Result";
import Nat64 "mo:base/Nat64";
import Nat32 "mo:base/Nat32";
import { now } = "mo:base/Time";
import Blob "mo:base/Blob";
import Map "mo:map/Map";
import WriteableBand "WriteableBand";

module DiodeAttachments {
    public type Attachment = {
        identity_hash : Blob;
        timestamp : Nat32;
        finalized: Bool;
        ciphertext : Blob;
    };

    let metadata_size : Nat64 = 45; // 32 + 4 + 4 + 8; // identity_hash + timestamp + finalized(nat32) + size(nat64)

    public type AttachmentMetadata = {
        timestamp : Nat32;
        finalized: Bool;
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

    public func new() : AttachmentStore {
        return {
            var attachments = WriteableBand.new();
            var first_entry_offset = 0;
            var end_offset = 0;
            var max_offset = 128 * 1024 * 1024;
            var next_entry_offset = null;
            var hash_to_offset = Map.new<Blob, Nat64>();
        };
    };

    public func allocate_attachment(store : AttachmentStore, identity_hash : Blob, size : Nat64) : Result.Result<Nat64, Text> {
        if (size == 0) {
            return #err("size must be greater than 0");
        };

        if (identity_hash.size() != 32) {
            return #err("identity_hash must be 32 bytes");
        };

        if (size > store.max_offset) {
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

        // Entry will not in the current space
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
        store.end_offset += size + metadata_size;
        Map.set<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash, offset);
        return #ok(offset);
    };

    public func delete_attachment(store : AttachmentStore, identity_hash : Blob) : Result.Result<(), Text> {
        Map.delete<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash);
        return #ok();
    };

    public func get_attachment(store : AttachmentStore, identity_hash : Blob) : Result.Result<Attachment, Text> {
        switch (Map.get<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash)) {
            case (null) {
                return #err("attachment not found");
            };
            case (?offset) {
                let meta_data = _read_metadata(store, offset);
                let ciphertext = WriteableBand.readBlob(store.attachments, offset + metadata_size, Nat64.toNat(meta_data.size));
                return #ok({ identity_hash = identity_hash; timestamp = meta_data.timestamp; finalized = meta_data.finalized; ciphertext = ciphertext });
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
        let timestamp = WriteableBand.readNat32(store.attachments, offset + 32);
        let size = WriteableBand.readNat64(store.attachments, offset + 32 + 4);
        let finalized = WriteableBand.readNat32(store.attachments, offset + 32 + 4 + 4) == 1;
        return { timestamp = timestamp; finalized = finalized; size = size };
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
                let identity_hash = WriteableBand.readBlob(store.attachments, offset, 32);
                // let timestamp = WriteableBand.readNat32(store.attachments, offset + 32);
                // Clear the timestamp to indicate that the entry is free
                WriteableBand.writeNat32(store.attachments, offset + 32, 0);
                let size = WriteableBand.readNat64(store.attachments, offset + 32 + 4); 
                Map.delete<Blob, Nat64>(store.hash_to_offset, Map.bhash, identity_hash);
                var next_entry_offset = offset + metadata_size + size;
                // Wrap around to the beginning of the band
                if (next_entry_offset + metadata_size + 1 > store.max_offset) {
                    store.next_entry_offset := ?0;
                    next_entry_offset := 0;
                };
                // This might be the beginning of the band (0) or the next entry somewhere in the middle
                let next_timestamp = WriteableBand.readNat32(store.attachments, next_entry_offset + 32);
                if (next_timestamp == 0) {
                    store.next_entry_offset := null;
                }
            };
        };
    };
};
