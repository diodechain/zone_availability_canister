import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import {test; suite} "mo:test/async";
import { DiodeAttachments } "../src/";
import Result "mo:base/Result";

actor {
  public func runTests() : async () {
    await suite("DiodeAttachments Tests", func() : async () {
      
      await test("Should create new attachment store", func() : async () {
        let store = DiodeAttachments.new(1000);
        assert store.max_offset == 1000;
        assert store.end_offset == 0;
        assert store.first_entry_offset == 0;
        assert store.next_entry_offset == null;
      });

      await test("Should write small attachment", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(1);
        let data = Blob.fromArray([1, 2, 3, 4, 5]);
        
        // Write attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
      });

      await test("Should write and get metadata for small attachment", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(1);
        let data = Blob.fromArray([1, 2, 3, 4, 5]);
        
        // Write attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
        
        // Get metadata
        switch (DiodeAttachments.get_attachment_metadata(store, hash)) {
          case (#ok(metadata)) {
            assert metadata.finalized == true;
            assert metadata.size == 5;
            assert metadata.timestamp > 0;
          };
          case (#err(err)) {
            assert false; // Should not error
          };
        };
      });

      await test("Should write and read small attachment", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(1);
        let data = Blob.fromArray([1, 2, 3, 4, 5]);
        
        // Write attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
        
        // Read attachment
        switch (DiodeAttachments.get_attachment(store, hash)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash;
            assert attachment.ciphertext == data;
            assert attachment.finalized == true;
            assert attachment.timestamp > 0;
          };
          case (#err(err)) {
            assert false; // Should not error
          };
        };
      });

      await test("Should handle large attachments using multi-step process", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(2);
        let total_size : Nat64 = 100;
        
        // Allocate attachment
        switch (DiodeAttachments.allocate_attachment(store, hash, total_size)) {
          case (#ok(offset)) {
            assert offset >= 0;
          };
          case (#err(err)) {
            assert false; // Should not error
          };
        };
        
        // Write chunks
        let chunk1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromNat(i)));
        let chunk2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromNat(i + 50)));
        
        assert isOk(DiodeAttachments.write_attachment_chunk(store, hash, 0, 50, chunk1));
        assert isOk(DiodeAttachments.write_attachment_chunk(store, hash, 50, 50, chunk2));
        
        // Try to read before finalization (should fail)
        switch (DiodeAttachments.read_attachment_chunk(store, hash, 0, 10)) {
          case (#ok(_)) {
            assert false; // Should fail - not finalized
          };
          case (#err(err)) {
            assert err == "attachment is not finalized";
          };
        };
        
        // Finalize attachment
        assert isOk(DiodeAttachments.finalize_attachment(store, hash));
        
        // Now should be able to read
        switch (DiodeAttachments.read_attachment_chunk(store, hash, 0, 10)) {
          case (#ok(chunk)) {
            assert chunk.size() == 10;
          };
          case (#err(err)) {
            assert false; // Should not error
          };
        };
        
        // Read full attachment
        switch (DiodeAttachments.get_attachment(store, hash)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash;
            assert attachment.finalized == true;
            assert attachment.ciphertext.size() == 100;
          };
          case (#err(err)) {
            assert false; // Should not error
          };
        };
      });

      await test("Should handle finalized behavior correctly", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(3);
        let data = Blob.fromArray([1, 2, 3]);
        
        // Write and finalize attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
        
        // Try to write chunk to finalized attachment (should fail)
        let new_chunk = Blob.fromArray([4, 5, 6]);
        switch (DiodeAttachments.write_attachment_chunk(store, hash, 0, 3, new_chunk)) {
          case (#ok(_)) {
            assert false; // Should fail - already finalized
          };
          case (#err(err)) {
            assert err == "attachment is finalized";
          };
        };
        
        // Try to finalize again (should succeed - idempotent)
        assert isOk(DiodeAttachments.finalize_attachment(store, hash));
      });

      await test("Should handle deletion correctly", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(4);
        let data = Blob.fromArray([1, 2, 3, 4]);
        
        // Write attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
        
        // Verify it exists
        switch (DiodeAttachments.get_attachment(store, hash)) {
          case (#ok(_)) { /* attachment exists */ };
          case (#err(_)) { assert false; };
        };
        
        // Delete attachment
        DiodeAttachments.delete_attachment(store, hash);
        
        // Verify it no longer exists
        switch (DiodeAttachments.get_attachment(store, hash)) {
          case (#ok(_)) {
            assert false; // Should not exist
          };
          case (#err(err)) {
            assert err == "attachment not found";
          };
        };
        
        // Metadata should also not exist
        switch (DiodeAttachments.get_attachment_metadata(store, hash)) {
          case (#ok(_)) {
            assert false; // Should not exist
          };
          case (#err(err)) {
            assert err == "attachment not found";
          };
        };
      });

      await test("Should handle ring-buffer behavior correctly", func() : async () {
        // Create store with small max_offset to trigger ring-buffer behavior
        let store = DiodeAttachments.new(200);
        let hash1 = make_hash(5);
        let hash2 = make_hash(6);
        let hash3 = make_hash(7);
        
        let data1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromNat(i)));
        let data2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromNat(i + 50)));
        let data3 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromNat(i + 100)));
        
        // Write first attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash1, data1));
        
        // Verify first attachment exists
        switch (DiodeAttachments.get_attachment(store, hash1)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash1;
          };
          case (#err(_)) { assert false; };
        };
        
        // Write second attachment (should trigger ring-buffer wrap)
        assert isOk(DiodeAttachments.write_attachment(store, hash2, data2));
        
        // First attachment should still exist (not overwritten yet)
        switch (DiodeAttachments.get_attachment(store, hash1)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash1;
          };
          case (#err(_)) { assert false; };
        };
        
        // Write third attachment (should overwrite first)
        assert isOk(DiodeAttachments.write_attachment(store, hash3, data3));
        
        // First attachment should be overwritten
        switch (DiodeAttachments.get_attachment(store, hash1)) {
          case (#ok(_)) {
            assert false; // Should be overwritten
          };
          case (#err(err)) {
            assert err == "attachment not found";
          };
        };
        
        // Second and third attachments should still exist
        switch (DiodeAttachments.get_attachment(store, hash2)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash2;
          };
          case (#err(_)) { assert false; };
        };
        
        switch (DiodeAttachments.get_attachment(store, hash3)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash3;
          };
          case (#err(_)) { assert false; };
        };
      });

      await test("Should handle error cases correctly", func() : async () {
        let store = DiodeAttachments.new(1000);
        
        // Test invalid hash size
        let invalid_hash = Blob.fromArray([1, 2, 3]); // Too small
        let data = Blob.fromArray([1, 2, 3, 4, 5]);
        
        switch (DiodeAttachments.write_attachment(store, invalid_hash, data)) {
          case (#ok(_)) {
            assert false; // Should fail
          };
          case (#err(err)) {
            assert err == "identity_hash must be 32 bytes";
          };
        };
        
        // Test zero size allocation
        let valid_hash = make_hash(8);
        switch (DiodeAttachments.allocate_attachment(store, valid_hash, 0)) {
          case (#ok(_)) {
            assert false; // Should fail
          };
          case (#err(err)) {
            assert err == "size must be greater than 0";
          };
        };
        
        // Test size too large
        switch (DiodeAttachments.allocate_attachment(store, valid_hash, 2000)) {
          case (#ok(_)) {
            assert false; // Should fail
          };
          case (#err(err)) {
            assert err == "size is too large";
          };
        };
        
        // Test reading non-existent attachment
        switch (DiodeAttachments.get_attachment(store, valid_hash)) {
          case (#ok(_)) {
            assert false; // Should fail
          };
          case (#err(err)) {
            assert err == "attachment not found";
          };
        };
      });

      await test("Should handle chunk reading correctly", func() : async () {
        let store = DiodeAttachments.new(1000);
        let hash = make_hash(9);
        let data = Blob.fromArray(Array.tabulate<Nat8>(100, func i = Nat8.fromNat(i)));
        
        // Write attachment
        assert isOk(DiodeAttachments.write_attachment(store, hash, data));
        
        // Read first chunk
        switch (DiodeAttachments.read_attachment_chunk(store, hash, 0, 10)) {
          case (#ok(chunk)) {
            assert chunk.size() == 10;
          };
          case (#err(_)) { assert false; };
        };
        
        // Read middle chunk
        switch (DiodeAttachments.read_attachment_chunk(store, hash, 50, 20)) {
          case (#ok(chunk)) {
            assert chunk.size() == 20;
          };
          case (#err(_)) { assert false; };
        };
        
        // Read chunk out of bounds
        switch (DiodeAttachments.read_attachment_chunk(store, hash, 95, 10)) {
          case (#ok(_)) {
            assert false; // Should fail
          };
          case (#err(err)) {
            assert err == "chunk out of bounds";
          };
        };
      });
    });
  };

  private func isOk(result : Result.Result<(), Text>) : Bool {
    switch (result) {
      case (#ok()) {
        return true;
      };
      case (#err(text)) {
        Debug.print(text);
        return false;
      };
    };
  };

  private func make_hash(n : Nat) : Blob {
    return make_blob(32, n);
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
}; 