import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import { test; suite } "mo:test/async";
import { DiodeFileSystem } "../src/";
import Result "mo:base/Result";

actor {
  public func runTests() : async () {
    await suite(
      "DiodeFileSystem Tests",
      func() : async () {

        await test(
          "Should create new file system",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            assert fs.max_storage == 1000;
            assert fs.current_storage == 0;
            assert fs.file_index == 1;
            assert fs.end_offset == 0;
            assert fs.next_entry_offset == null;
          },
        );

        await test(
          "Should create directory",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);

            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            let ?directory = DiodeFileSystem.get_directory(fs, directory_id);
            assert directory.id == directory_id;
            assert directory.name_hash == name_hash;
            assert directory.parent_id == null;
            assert directory.child_directories.size() == 0;
            assert directory.child_files.size() == 0;

            let ?directory_by_name = DiodeFileSystem.get_directory_by_name(fs, name_hash);
            assert directory_by_name == directory;
          },
        );

        await test(
          "Should create nested directories",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let parent_id = make_blob(32, 1);
            let child_id = make_blob(32, 2);
            let parent_name = make_blob(32, 3);
            let child_name = make_blob(32, 4);

            // Create parent directory
            assert isOk(DiodeFileSystem.create_directory(fs, parent_id, parent_name, null));

            // Create child directory
            assert isOk(DiodeFileSystem.create_directory(fs, child_id, child_name, ?parent_id));

            let ?parent = DiodeFileSystem.get_directory(fs, parent_id);
            assert parent.child_directories.size() == 1;
            assert parent.child_directories[0] == child_id;

            let ?child = DiodeFileSystem.get_directory(fs, child_id);
            assert child.parent_id == ?parent_id;

            let children = DiodeFileSystem.get_child_directories(fs, parent_id);
            assert children.size() == 1;
            assert children[0].id == child_id;
          },
        );

        await test(
          "Should fail creating directory with invalid parameters",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let valid_id = make_blob(32, 1);
            let valid_name = make_blob(32, 2);
            let invalid_id = make_blob(16, 1);
            let invalid_name = make_blob(16, 2);

            // Test invalid directory_id size
            switch (DiodeFileSystem.create_directory(fs, invalid_id, valid_name, null)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "directory_id must be 32 bytes"; };
            };

            // Test invalid name_hash size
            switch (DiodeFileSystem.create_directory(fs, valid_id, invalid_name, null)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "name_hash must be 32 bytes"; };
            };

            // Test creating same directory twice
            assert isOk(DiodeFileSystem.create_directory(fs, valid_id, valid_name, null));
            switch (DiodeFileSystem.create_directory(fs, valid_id, valid_name, null)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "directory already exists"; };
            };
          },
        );

        await test(
          "Should add file to directory",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory first
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Add file
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash, content_hash, ciphertext));

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.id == 1;
                assert file.directory_id == directory_id;
                assert file.name_hash == name_hash;
                assert file.content_hash == content_hash;
                assert file.ciphertext == ciphertext;
                assert file.size == 5;
                assert file.finalized == true;
              };
              case (#err(_)) { assert false; };
            };

            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 1;
            assert files[0].id == 1;
          },
        );

        await test(
          "Should add multiple files to directory",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let content_hash1 = make_blob(32, 4);
            let content_hash2 = make_blob(32, 5);
            let ciphertext1 = Blob.fromArray([1, 2, 3]);
            let ciphertext2 = Blob.fromArray([4, 5, 6, 7]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, null));

            // Add first file
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash1, content_hash1, ciphertext1));

            // Add second file
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash2, content_hash2, ciphertext2));

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.id == 1;
                assert file1.size == 3;
                assert file1.finalized == true;
              };
              case (#err(_)) { assert false; };
            };

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.id == 2;
                assert file2.size == 4;
                assert file2.finalized == true;
              };
              case (#err(_)) { assert false; };
            };

            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 2;
          },
        );

        await test(
          "Should fail adding file with invalid parameters",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let valid_id = make_blob(32, 1);
            let valid_hash = make_blob(32, 2);
            let valid_ciphertext = Blob.fromArray([1, 2, 3]);
            let invalid_id = make_blob(16, 1);
            let invalid_hash = make_blob(16, 2);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, valid_id, valid_hash, null));

            // Test invalid directory_id size
            switch (DiodeFileSystem.add_file(fs, invalid_id, valid_hash, valid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "directory_id must be 32 bytes"; };
            };

            // Test invalid name_hash size
            switch (DiodeFileSystem.add_file(fs, valid_id, invalid_hash, valid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "name_hash must be 32 bytes"; };
            };

            // Test invalid content_hash size
            switch (DiodeFileSystem.add_file(fs, valid_id, valid_hash, invalid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "content_hash must be 32 bytes"; };
            };

            // Test adding to non-existent directory
            let non_existent_id = make_blob(32, 999);
            switch (DiodeFileSystem.add_file(fs, non_existent_id, valid_hash, valid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "directory not found"; };
            };
          },
        );

        await test(
          "Should handle ring-buffer behavior correctly",
          func() : async () {
            // Create file system with small storage to trigger ring-buffer behavior
            let fs = DiodeFileSystem.new(200);
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let content_hash1 = make_blob(32, 4);
            let content_hash2 = make_blob(32, 5);
            let ciphertext1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i)));
            let ciphertext2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 50)));

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, null));

            // Add first file
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash1, content_hash1, ciphertext1));

            // Verify first file exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.content_hash == content_hash1;
              };
              case (#err(_)) { assert false; };
            };

            // Add second file (should trigger ring-buffer wrap)
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash2, content_hash2, ciphertext2));

            // First file should still exist (not overwritten yet)
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1_after)) {
                assert file1_after.content_hash == content_hash1;
              };
              case (#err(_)) { assert false; };
            };

            // Add third file (should overwrite first)
            let name_hash3 = make_blob(32, 6);
            let content_hash3 = make_blob(32, 7);
            let ciphertext3 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 100)));
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash3, content_hash3, ciphertext3));

            // First file should be overwritten
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "file not found"; };
            };

            // Second and third files should still exist
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.content_hash == content_hash2;
              };
              case (#err(_)) { assert false; };
            };

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash3)) {
              case (#ok(file3)) {
                assert file3.content_hash == content_hash3;
              };
              case (#err(_)) { assert false; };
            };
          },
        );

        await test(
          "Should handle duplicate file content correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let content_hash = make_blob(32, 4);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, null));

            // Add first file
            let result1 = DiodeFileSystem.add_file(fs, directory_id, name_hash1, content_hash, ciphertext);
            assert isOkNat32(result1);

            // Try to add same content with different name
            let result2 = DiodeFileSystem.add_file(fs, directory_id, name_hash2, content_hash, ciphertext);
            assert isOkNat32(result2);

            // Should return the same file ID
            switch (result1, result2) {
              case (#ok(id1), #ok(id2)) {
                assert id1 == id2;
              };
              case (_, _) { assert false; };
            };

            // Should only have one file in the system
            assert DiodeFileSystem.get_file_count(fs) == 1;
          },
        );

        await test(
          "Should get files by ID correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Add file
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash, content_hash, ciphertext));

            // Get file by ID
            let file = DiodeFileSystem.get_file_by_id(fs, 1);
            assert file.id == 1;
            assert file.content_hash == content_hash;
            assert file.ciphertext == ciphertext;
            assert file.finalized == true;
          },
        );

        await test(
          "Should handle empty directory correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Get files in empty directory
            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 0;

            // Get child directories of empty directory
            let children = DiodeFileSystem.get_child_directories(fs, directory_id);
            assert children.size() == 0;
          },
        );

        await test(
          "Should handle usage statistics correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);

            // Initial state
            assert DiodeFileSystem.get_usage(fs) == 0;
            assert DiodeFileSystem.get_max_usage(fs) == 1000;
            assert DiodeFileSystem.get_file_count(fs) == 0;
            assert DiodeFileSystem.get_directory_count(fs) == 0;

            // Create directory
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            assert DiodeFileSystem.get_directory_count(fs) == 1;

            // Add file
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash, content_hash, ciphertext));

            assert DiodeFileSystem.get_file_count(fs) == 1;
          },
        );

        await test(
          "Should handle set_max_storage correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            assert DiodeFileSystem.get_max_usage(fs) == 1000;

            DiodeFileSystem.set_max_storage(fs, 2000);
            assert DiodeFileSystem.get_max_usage(fs) == 2000;
          },
        );

        await test(
          "Should handle chunked file upload correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Allocate file
            switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 10)) {
              case (#ok(file_id)) {
                assert file_id == 1;
              };
              case (#err(_)) { assert false; };
            };

            // Write chunks
            let chunk1 = Blob.fromArray([1, 2, 3, 4, 5]);
            let chunk2 = Blob.fromArray([6, 7, 8, 9, 10]);
            
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk1)) {
              case (#ok()) {};
              case (#err(_)) { assert false; };
            };
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 5, chunk2)) {
              case (#ok()) {};
              case (#err(_)) { assert false; };
            };

            // File should not be finalized yet
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == false;
              };
              case (#err(_)) { assert false; };
            };

            // Finalize file
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false; };
            };

            // File should be finalized now
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == true;
                assert file.ciphertext == ciphertext;
                assert file.size == 10;
              };
              case (#err(_)) { assert false; };
            };

            // Check directory contains the file
            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 1;
            assert files[0].id == 1;
          },
        );

        await test(
          "Should handle chunked file download correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

            // Create directory and add file normally
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));
            assert isOkNat32(DiodeFileSystem.add_file(fs, directory_id, name_hash, content_hash, ciphertext));

            // Read chunks
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
              case (#ok(chunk1)) {
                assert chunk1 == Blob.fromArray([1, 2, 3, 4, 5]);
              };
              case (#err(_)) { assert false; };
            };

            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 5, 5)) {
              case (#ok(chunk2)) {
                assert chunk2 == Blob.fromArray([6, 7, 8, 9, 10]);
              };
              case (#err(_)) { assert false; };
            };

            // Test out of bounds
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 8, 5)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "chunk out of bounds"; };
            };
          },
        );

        await test(
          "Should handle chunked upload error cases correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Try to write chunk to non-existent file
            let chunk = Blob.fromArray([1, 2, 3]);
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "file not found"; };
            };

            // Allocate file
            assert isOkNat32(DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5));

            // Try to write out of bounds chunk
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 3, chunk)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "chunk out of bounds"; };
            };

            // Finalize file
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false; };
            };

            // Try to write to finalized file
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk)) {
              case (#ok(_)) { assert false; };
              case (#err(err)) { assert err == "file is already finalized"; };
            };
          },
        );

        await test(
          "Should use write_file for small files correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

            // Use write_file (should allocate, write chunk, and finalize in one call)
            switch (DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext)) {
              case (#ok(file_id)) {
                assert file_id == 1;
              };
              case (#err(_)) { assert false; };
            };

            // File should be finalized
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == true;
                assert file.ciphertext == ciphertext;
                assert file.size == 5;
              };
              case (#err(_)) { assert false; };
            };

            // Check directory contains the file
            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 1;
            assert files[0].id == 1;
          },
        );
      },
    );
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



  private func isOkNat32(result : Result.Result<Nat32, Text>) : Bool {
    switch (result) {
      case (#ok(n)) {
        return true;
      };
      case (#err(text)) {
        Debug.print(text);
        return false;
      };
    };
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
}; 