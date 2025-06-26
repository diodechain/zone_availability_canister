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
        let chunk1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i)));
        let chunk2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 50)));
        
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
        
        let data1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i)));
        let data2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 50)));
        let data3 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 100)));
        
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

      await test("Should handle ring-buffer edge cases at buffer boundaries #1", func() : async () {
        // Test 1: End of data hits exactly at buffer end (size + metadata_size == max_offset)
        // metadata_size = 48, so we'll test with various sizes around the boundary
        
        // Test case 1: size + metadata_size == max_offset (exact fit)
        let store1 = DiodeAttachments.new(1000); // max_offset = 1000
        let hash1 = make_hash(10);
        let data1 = Blob.fromArray(Array.tabulate<Nat8>(952, func i = Nat8.fromIntWrap(i))); // 952 + 48 = 1000
        
        // This should fit exactly
        assert isOk(DiodeAttachments.write_attachment(store1, hash1, data1));
        
        // Verify it exists
        switch (DiodeAttachments.get_attachment(store1, hash1)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash1;
            assert attachment.ciphertext.size() == 952;
          };
          case (#err(_)) { assert false; };
        };
      });

      await test("Should handle ring-buffer edge cases at buffer boundaries #2", func() : async () {
        // Test case 2: size + metadata_size == max_offset - 1 (should fit)
        let store2 = DiodeAttachments.new(1000);
        let hash2 = make_hash(11);
        let data2 = Blob.fromArray(Array.tabulate<Nat8>(951, func i = Nat8.fromIntWrap(i))); // 951 + 48 = 999
        
        assert isOk(DiodeAttachments.write_attachment(store2, hash2, data2));

      });

      await test("Should handle ring-buffer edge cases at buffer boundaries #3", func() : async () {
        // Test case 3: size + metadata_size == max_offset + 1 (should trigger wrap)
        let store3 = DiodeAttachments.new(1000);
        let hash3 = make_hash(12);
        let data3 = Blob.fromArray(Array.tabulate<Nat8>(953, func i = Nat8.fromIntWrap(i))); // 953 + 48 = 1001
        
        // This should trigger ring-buffer wrap
        assert isOk(DiodeAttachments.write_attachment(store3, hash3, data3));
        
        // Test case 4: Test the boundary condition with a second attachment
        let hash4 = make_hash(13);
        let data4 = Blob.fromArray(Array.tabulate<Nat8>(500, func i = Nat8.fromIntWrap(i)));
        
        // This should overwrite the first attachment due to ring-buffer behavior
        assert isOk(DiodeAttachments.write_attachment(store3, hash4, data4));
        
        // First attachment should be overwritten
        switch (DiodeAttachments.get_attachment(store3, hash3)) {
          case (#ok(_)) {
            assert false; // Should be overwritten
          };
          case (#err(err)) {
            assert err == "attachment not found";
          };
        };
        
        // Second attachment should exist
        switch (DiodeAttachments.get_attachment(store3, hash4)) {
          case (#ok(attachment)) {
            assert attachment.identity_hash == hash4;
          };
          case (#err(_)) { assert false; };
        };
      });

      await test("Should handle multiple ring-buffer loops with different sizes", func() : async () {
        // Create a store that will require multiple loops
        let store = DiodeAttachments.new(2000); // Small enough to trigger multiple loops
        
        // First loop: Write attachments that will be overwritten
        let hash1 = make_hash(20);
        let hash2 = make_hash(21);
        let data1 = Blob.fromArray(Array.tabulate<Nat8>(800, func i = Nat8.fromIntWrap(i)));
        let data2 = Blob.fromArray(Array.tabulate<Nat8>(800, func i = Nat8.fromIntWrap(i + 800)));
        
        assert isOk(DiodeAttachments.write_attachment(store, hash1, data1));
        assert isOk(DiodeAttachments.write_attachment(store, hash2, data2));
        
        // Verify both exist
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash1));
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash2));
        
        // Second loop: Write larger attachment that will overwrite both
        let hash3 = make_hash(22);
        let data3 = Blob.fromArray(Array.tabulate<Nat8>(1500, func i = Nat8.fromIntWrap(i + 1600)));
        
        assert isOk(DiodeAttachments.write_attachment(store, hash3, data3));
        
        // First two should be overwritten
        switch (DiodeAttachments.get_attachment(store, hash1)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        switch (DiodeAttachments.get_attachment(store, hash2)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        // Third should exist
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash3));
        
        // Third loop: Write multiple smaller attachments
        let hash4 = make_hash(23);
        let hash5 = make_hash(24);
        let data4 = Blob.fromArray(Array.tabulate<Nat8>(400, func i = Nat8.fromIntWrap(i + 3100)));
        let data5 = Blob.fromArray(Array.tabulate<Nat8>(400, func i = Nat8.fromIntWrap(i + 3500)));
        
        assert isOk(DiodeAttachments.write_attachment(store, hash4, data4));
        assert isOk(DiodeAttachments.write_attachment(store, hash5, data5));
        
        // Third attachment should be overwritten
        switch (DiodeAttachments.get_attachment(store, hash3)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        // Fourth and fifth should exist
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash4));
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash5));
        
        // Fourth loop: Write one more attachment to complete the cycle
        let hash6 = make_hash(25);
        let data6 = Blob.fromArray(Array.tabulate<Nat8>(600, func i = Nat8.fromIntWrap(i + 3900)));
        
        assert isOk(DiodeAttachments.write_attachment(store, hash6, data6));
        
        // Fourth should be overwritten
        switch (DiodeAttachments.get_attachment(store, hash4)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        // Fifth and sixth should exist
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash5));
        assert attachmentExists(DiodeAttachments.get_attachment(store, hash6));
      });

      await test("Should handle ring-buffer with exact boundary calculations", func() : async () {
        // Test precise boundary calculations to catch off-by-one errors
        
        // Test 1: max_offset = 1000, metadata_size = 48, so max data size = 952
        let store1 = DiodeAttachments.new(1000);
        let hash1 = make_hash(30);
        let data1 = Blob.fromArray(Array.tabulate<Nat8>(952, func i = Nat8.fromIntWrap(i)));
        
        // This should fit exactly: 952 + 48 = 1000
        assert isOk(DiodeAttachments.write_attachment(store1, hash1, data1));
        
        // Test 2: Try to write one more byte (should trigger wrap)
        let hash2 = make_hash(31);
        let data2 = Blob.fromArray(Array.tabulate<Nat8>(953, func i = Nat8.fromIntWrap(i)));
        
        // This should trigger ring-buffer wrap: 953 + 48 = 1001 > 1000
        assert isOk(DiodeAttachments.write_attachment(store1, hash2, data2));
        
        // First attachment should be overwritten
        switch (DiodeAttachments.get_attachment(store1, hash1)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        // Second should exist
        assert attachmentExists(DiodeAttachments.get_attachment(store1, hash2));
        
        // Test 3: Test with exactly one byte less than boundary
        let store2 = DiodeAttachments.new(1000);
        let hash3 = make_hash(32);
        let data3 = Blob.fromArray(Array.tabulate<Nat8>(951, func i = Nat8.fromIntWrap(i)));
        
        // This should fit: 951 + 48 = 999 < 1000
        assert isOk(DiodeAttachments.write_attachment(store2, hash3, data3));
        
        // Try to write a small second attachment (should fit)
        let hash4 = make_hash(33);
        let data4 = Blob.fromArray([1, 2, 3, 4, 5]);
        
        // This should also fit: 5 + 48 = 53, total 999 + 53 = 1052 > 1000, so should wrap
        assert isOk(DiodeAttachments.write_attachment(store2, hash4, data4));
        
        // First should be overwritten
        switch (DiodeAttachments.get_attachment(store2, hash3)) {
          case (#ok(_)) { assert false; };
          case (#err(err)) { assert err == "attachment not found"; };
        };
        
        // Second should exist
        assert attachmentExists(DiodeAttachments.get_attachment(store2, hash4));
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
        let data = Blob.fromArray(Array.tabulate<Nat8>(100, func i = Nat8.fromIntWrap(i)));
        
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

  private func attachmentExists(result : Result.Result<DiodeAttachments.Attachment, Text>) : Bool {
    switch (result) {
      case (#ok(_)) {
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