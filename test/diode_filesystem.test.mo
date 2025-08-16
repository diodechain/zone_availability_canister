import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Map "mo:map/Map";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import { test; suite } "mo:test/async";
import { DiodeFileSystem } "../src/";
import Result "mo:base/Result";

persistent actor {
  public func runTests() : async () {
    await suite(
      "DiodeFileSystem Tests",
      func() : async () {

        await test(
          "Should create new file system with root directory",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            assert fs.max_storage == 1000;
            assert fs.current_storage == 0;
            assert fs.file_index == 1;
            assert fs.end_offset == 0;
            assert fs.next_entry_offset == null;

            // Root directory should be automatically created
            assert DiodeFileSystem.get_directory_count(fs) == 1;
            let ?root = DiodeFileSystem.get_root_directory(fs);
            assert root.id == DiodeFileSystem.ROOT_DIRECTORY_ID;
            assert root.parent_id == null;
            assert root.child_directories.size() == 0;
            assert root.child_files.size() == 0;
          },
        );

        await test(
          "Should create directory under root",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);

            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            let ?directory = DiodeFileSystem.get_directory(fs, directory_id);
            assert directory.id == directory_id;
            assert directory.metadata_ciphertext == name_hash;
            assert directory.parent_id == ?DiodeFileSystem.ROOT_DIRECTORY_ID;
            assert directory.child_directories.size() == 0;
            assert directory.child_files.size() == 0;

            // Root should now contain this directory
            let ?root = DiodeFileSystem.get_root_directory(fs);
            assert root.child_directories.size() == 1;
            assert root.child_directories[0] == directory_id;
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

            // Create parent directory under root
            assert isOk(DiodeFileSystem.create_directory(fs, parent_id, parent_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

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
            let invalid_id = make_blob(6, 1);

            // Test invalid directory_id size
            switch (DiodeFileSystem.create_directory(fs, invalid_id, valid_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "directory_id must be at least 8 bytes";
              };
            };

            // Test creating directory without parent (orphaned directory)
            switch (DiodeFileSystem.create_directory(fs, valid_id, valid_name, null)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "cannot create directory without parent - only root directory can have null parent";
              };
            };

            // Test creating directory with reserved root ID
            switch (DiodeFileSystem.create_directory(fs, DiodeFileSystem.ROOT_DIRECTORY_ID, valid_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "cannot create directory with reserved root ID";
              };
            };

            // Test creating directory with non-existent parent
            let non_existent_parent = make_blob(32, 999);
            switch (DiodeFileSystem.create_directory(fs, valid_id, valid_name, ?non_existent_parent)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "parent directory not found" };
            };

            // Test creating same directory twice
            assert isOk(DiodeFileSystem.create_directory(fs, valid_id, valid_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            switch (DiodeFileSystem.create_directory(fs, valid_id, valid_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "directory already exists" };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add file
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext));

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.id == 1;
                assert file.directory_id == directory_id;
                assert file.metadata_ciphertext == name_hash;
                assert file.content_hash == content_hash;
                assert file.size == 5;
                assert file.finalized == true;
                // Verify ciphertext by reading the chunk
                switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
                  case (#ok(read_ciphertext)) {
                    assert read_ciphertext == ciphertext;
                  };
                  case (#err(_)) { assert false };
                };
              };
              case (#err(_)) { assert false };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add first file
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash1, content_hash1, ciphertext1));

            // Add second file
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash2, content_hash2, ciphertext2));

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.id == 1;
                assert file1.size == 3;
                assert file1.finalized == true;
              };
              case (#err(_)) { assert false };
            };

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.id == 2;
                assert file2.size == 4;
                assert file2.finalized == true;
              };
              case (#err(_)) { assert false };
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
            let invalid_id = make_blob(4, 1);
            let invalid_hash = make_blob(12, 2);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, valid_id, valid_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Test invalid directory_id size
            switch (DiodeFileSystem.write_file(fs, invalid_id, valid_hash, valid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "directory_id must be at least 8 bytes";
              };
            };

            // Test invalid content_hash size
            switch (DiodeFileSystem.write_file(fs, valid_id, valid_hash, invalid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "content_hash must be at least 16 bytes";
              };
            };

            // Test adding to non-existent directory
            let non_existent_id = make_blob(32, 999);
            switch (DiodeFileSystem.write_file(fs, non_existent_id, valid_hash, valid_hash, valid_ciphertext)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "directory not found" };
            };
          },
        );

        await test(
          "Should handle ring-buffer behavior correctly",
          func() : async () {
            // Create file system with capacity for exactly 2 files (120 bytes each = 256 bytes total)
            // Each file: 120 bytes content + 8 bytes metadata = 128 bytes
            let fs = DiodeFileSystem.new(300); // Allows 2 files (256 bytes) but not 3 files (384 bytes)
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let name_hash3 = make_blob(32, 4);
            let content_hash1 = make_blob(32, 5);
            let content_hash2 = make_blob(32, 6);
            let content_hash3 = make_blob(32, 7);
            let ciphertext1 = Blob.fromArray(Array.tabulate<Nat8>(120, func i = Nat8.fromIntWrap(i)));
            let ciphertext2 = Blob.fromArray(Array.tabulate<Nat8>(120, func i = Nat8.fromIntWrap(i + 50)));
            let ciphertext3 = Blob.fromArray(Array.tabulate<Nat8>(120, func i = Nat8.fromIntWrap(i + 100)));

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add first file (128 bytes)
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash1, content_hash1, ciphertext1));

            // Verify first file exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.content_hash == content_hash1;
                assert file1.size == 120;
              };
              case (#err(_)) { assert false };
            };

            // Add second file (128 bytes, total 256 bytes - should fit in 300 bytes)
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash2, content_hash2, ciphertext2));

            // Both files should exist
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.content_hash == content_hash1;
              };
              case (#err(_)) { assert false };
            };

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.content_hash == content_hash2;
              };
              case (#err(_)) { assert false };
            };

            // Add third file (128 bytes, total would be 384 bytes > 300 bytes limit)
            // Should remove first file to make space
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash3, content_hash3, ciphertext3));

            // First file should be removed (oldest file removed first)
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(_)) { assert false }; // Should not exist
              case (#err(err)) { assert err == "file not found" };
            };

            // Second and third files should still exist
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.content_hash == content_hash2;
              };
              case (#err(_)) { assert false };
            };

            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash3)) {
              case (#ok(file3)) {
                assert file3.content_hash == content_hash3;
              };
              case (#err(_)) { assert false };
            };
          },
        );

        await test(
          "Should handle ring-buffer wrapping behavior",
          func() : async () {
            // Test wrapping when files don't fit at current position
            // Create filesystem that can fit 1 file normally, but needs wrapping for a second
            let fs = DiodeFileSystem.new(140); // Between 1 file (128 bytes) and 2 files (256 bytes)
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let content_hash1 = make_blob(32, 4);
            let content_hash2 = make_blob(32, 5);
            let ciphertext1 = Blob.fromArray(Array.tabulate<Nat8>(120, func i = Nat8.fromIntWrap(i)));
            let ciphertext2 = Blob.fromArray(Array.tabulate<Nat8>(120, func i = Nat8.fromIntWrap(i + 50)));

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add first file at position 0 (128 bytes)
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash1, content_hash1, ciphertext1));

            // Verify first file exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(file1)) {
                assert file1.content_hash == content_hash1;
              };
              case (#err(_)) { assert false };
            };

            // Add second file - won't fit (128 + 128 = 256 > 140), should trigger removal of first file
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash2, content_hash2, ciphertext2));

            // First file should be removed due to wrapping collision
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash1)) {
              case (#ok(_)) { assert false }; // Should not exist
              case (#err(err)) { assert err == "file not found" };
            };

            // Second file should exist
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash2)) {
              case (#ok(file2)) {
                assert file2.content_hash == content_hash2;
              };
              case (#err(_)) { assert false };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add first file
            let result1 = DiodeFileSystem.write_file(fs, directory_id, name_hash1, content_hash, ciphertext);
            assert isOkNat(result1);

            // Try to add same content with different name
            let result2 = DiodeFileSystem.write_file(fs, directory_id, name_hash2, content_hash, ciphertext);
            assert isOkNat(result2);

            // Should return the same file ID
            switch (result1, result2) {
              case (#ok(id1), #ok(id2)) {
                assert id1 != id2;
              };
              case (_, _) { assert false };
            };

            // Should have two files in the system
            assert DiodeFileSystem.get_file_count(fs) == 2;
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add file
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext));

            // Get file by ID
            let ?file = DiodeFileSystem.get_file_by_id(fs, 1) else {
              assert false;
              return;
            };
            assert file.id == 1;
            assert file.content_hash == content_hash;
            assert file.finalized == true;
            // Verify ciphertext by reading the chunk
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
              case (#ok(read_ciphertext)) {
                assert read_ciphertext == ciphertext;
              };
              case (#err(_)) { assert false };
            };
          },
        );

        await test(
          "Should handle empty directory correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

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

            // Initial state (with auto-created root directory)
            assert DiodeFileSystem.get_usage(fs) == 0;
            assert DiodeFileSystem.get_max_usage(fs) == 1000;
            assert DiodeFileSystem.get_file_count(fs) == 0;
            assert DiodeFileSystem.get_directory_count(fs) == 1; // Root directory auto-created

            // Create directory
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            assert DiodeFileSystem.get_directory_count(fs) == 2; // Root + created directory

            // Add file
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext));

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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Allocate file
            switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 10)) {
              case (#ok(file)) {
                assert file.id == 1;
              };
              case (#err(_)) { assert false };
            };

            // Write chunks
            let chunk1 = Blob.fromArray([1, 2, 3, 4, 5]);
            let chunk2 = Blob.fromArray([6, 7, 8, 9, 10]);

            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk1)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 5, chunk2)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // File should not be finalized yet
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == false;
              };
              case (#err(_)) { assert false };
            };

            // Finalize file
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // File should be finalized now
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == true;
                assert file.size == 10;
                // Verify ciphertext by reading the chunk
                switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 10)) {
                  case (#ok(read_ciphertext)) {
                    assert read_ciphertext == ciphertext;
                  };
                  case (#err(_)) { assert false };
                };
              };
              case (#err(_)) { assert false };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext));

            // Read chunks
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
              case (#ok(chunk1)) {
                assert chunk1 == Blob.fromArray([1, 2, 3, 4, 5]);
              };
              case (#err(_)) { assert false };
            };

            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 5, 5)) {
              case (#ok(chunk2)) {
                assert chunk2 == Blob.fromArray([6, 7, 8, 9, 10]);
              };
              case (#err(_)) { assert false };
            };

            // Test out of bounds
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 8, 5)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "chunk out of bounds" };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Try to write chunk to non-existent file
            let chunk = Blob.fromArray([1, 2, 3]);
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };

            // Allocate file
            assert isOkFile(DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5));

            // Try to write out of bounds chunk
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 3, chunk)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "chunk out of bounds" };
            };

            // Finalize file
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Try to write to finalized file
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, chunk)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file is already finalized" };
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
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Use write_file (should allocate, write chunk, and finalize in one call)
            switch (DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext)) {
              case (#ok(file_id)) {
                assert file_id == 1;
              };
              case (#err(_)) { assert false };
            };

            // File should be finalized
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == true;
                assert file.size == 5;
                // Verify ciphertext by reading the chunk
                switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
                  case (#ok(read_ciphertext)) {
                    assert read_ciphertext == ciphertext;
                  };
                  case (#err(_)) { assert false };
                };
              };
              case (#err(_)) { assert false };
            };

            // Check directory contains the file
            let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files.size() == 1;
            assert files[0].id == 1;
          },
        );

        await test(
          "Should handle finalize_file idempotently",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Allocate file
            switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5)) {
              case (#ok(file)) {
                assert file.id == 1;
              };
              case (#err(_)) { assert false };
            };

            // Write chunk
            switch (DiodeFileSystem.write_file_chunk(fs, content_hash, 0, ciphertext)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Finalize file first time
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Check directory has one file
            let files_after_first = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_after_first.size() == 1;

            // Finalize file second time (should be idempotent)
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Check directory still has only one file (no duplicates)
            let files_after_second = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_after_second.size() == 1;

            // Finalize file third time (should still be idempotent)
            switch (DiodeFileSystem.finalize_file(fs, content_hash)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Check directory still has only one file
            let files_after_third = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_after_third.size() == 1;
            assert files_after_third[0].id == 1;
            assert files_after_third[0].finalized == true;
          },
        );

        await test(
          "Should handle delete_file correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add file normally
            assert isOkNat(DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, ciphertext));

            // Verify file exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.id == 1;
                assert file.finalized == true;
              };
              case (#err(_)) { assert false };
            };

            // Verify directory contains the file
            let files_before = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_before.size() == 1;

            // Get initial storage usage
            let storage_before = DiodeFileSystem.get_usage(fs);
            assert storage_before > 0;

            // Delete the file
            switch (DiodeFileSystem.delete_file(fs, files_before[0].id)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Verify file no longer exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };

            // Verify directory no longer contains the file
            let files_after = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_after.size() == 0;

            // Verify storage usage decreased
            let storage_after = DiodeFileSystem.get_usage(fs);
            assert storage_after < storage_before;

            // Try to delete non-existent file
            switch (DiodeFileSystem.delete_file(fs, files_before[0].id + 1)) {
              case (#ok()) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };
          },
        );

        await test(
          "Should handle delete_file for unfinalized file correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);

            // Create directory
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Allocate file but don't finalize
            switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5)) {
              case (#ok(file)) {
                assert file.id == 1;
              };
              case (#err(_)) { assert false };
            };

            // Verify file exists but not finalized
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(file)) {
                assert file.finalized == false;
              };
              case (#err(_)) { assert false };
            };

            // Directory should not contain the file (not finalized)
            let files_before = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_before.size() == 0;

            // Delete the unfinalized file
            switch (DiodeFileSystem.delete_file(fs, 1)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Verify file no longer exists
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };

            // Directory should still be empty
            let files_after = DiodeFileSystem.get_files_in_directory(fs, directory_id);
            assert files_after.size() == 0;
          },
        );

        await test(
          "Should access root directory correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);

            // Get root directory through different methods
            let ?root1 = DiodeFileSystem.get_root_directory(fs);
            let ?root2 = DiodeFileSystem.get_directory(fs, DiodeFileSystem.ROOT_DIRECTORY_ID);

            // Both should be the same
            assert root1.id == root2.id;
            assert root1.id == DiodeFileSystem.ROOT_DIRECTORY_ID;
            assert root1.parent_id == null;
            assert root1.child_directories.size() == 0;
            assert root1.child_files.size() == 0;

            // Create a child directory and verify root is updated
            let child_id = make_blob(32, 1);
            let child_name = make_blob(32, 2);
            assert isOk(DiodeFileSystem.create_directory(fs, child_id, child_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            let ?updated_root = DiodeFileSystem.get_root_directory(fs);
            assert updated_root.child_directories.size() == 1;
            assert updated_root.child_directories[0] == child_id;
          },
        );

        await test(
          "Should prevent orphaned directories comprehensively",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);

            // Test 1: Cannot create directory with null parent
            switch (DiodeFileSystem.create_directory(fs, directory_id, name_hash, null)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "cannot create directory without parent - only root directory can have null parent";
              };
            };

            // Test 2: Cannot create directory with non-existent parent
            let fake_parent = make_blob(32, 999);
            switch (DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?fake_parent)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "parent directory not found" };
            };

            // Test 3: Can create directory with valid parent (root)
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Test 4: Can create directory with valid parent (another directory)
            let child_id = make_blob(32, 3);
            let child_name = make_blob(32, 4);
            assert isOk(DiodeFileSystem.create_directory(fs, child_id, child_name, ?directory_id));

            // Verify the hierarchy
            let ?root = DiodeFileSystem.get_root_directory(fs);
            assert root.child_directories.size() == 1;
            assert root.child_directories[0] == directory_id;

            let ?parent = DiodeFileSystem.get_directory(fs, directory_id);
            assert parent.child_directories.size() == 1;
            assert parent.child_directories[0] == child_id;

            let ?child = DiodeFileSystem.get_directory(fs, child_id);
            assert child.parent_id == ?directory_id;
          },
        );

        await test(
          "Should enforce root directory uniqueness",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let name_hash = make_blob(32, 1);

            // Cannot create another directory with the root ID
            switch (DiodeFileSystem.create_directory(fs, DiodeFileSystem.ROOT_DIRECTORY_ID, name_hash, ?DiodeFileSystem.ROOT_DIRECTORY_ID)) {
              case (#ok(_)) { assert false };
              case (#err(err)) {
                assert err == "cannot create directory with reserved root ID";
              };
            };

            // Root directory should still exist and be unchanged
            let ?root = DiodeFileSystem.get_root_directory(fs);
            assert root.id == DiodeFileSystem.ROOT_DIRECTORY_ID;
            assert root.parent_id == null;
            assert root.child_directories.size() == 0;
          },
        );

        await test(
          "Should handle complex directory hierarchy correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);

            // Create a 3-level hierarchy: root -> level1 -> level2
            let level1_id = make_blob(32, 1);
            let level2_id = make_blob(32, 2);
            let level1_name = make_blob(32, 3);
            let level2_name = make_blob(32, 4);

            // Create level 1 under root
            assert isOk(DiodeFileSystem.create_directory(fs, level1_id, level1_name, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Create level 2 under level 1
            assert isOk(DiodeFileSystem.create_directory(fs, level2_id, level2_name, ?level1_id));

            // Verify hierarchy
            let ?root = DiodeFileSystem.get_root_directory(fs);
            assert root.child_directories.size() == 1;
            assert root.child_directories[0] == level1_id;

            let ?level1 = DiodeFileSystem.get_directory(fs, level1_id);
            assert level1.parent_id == ?DiodeFileSystem.ROOT_DIRECTORY_ID;
            assert level1.child_directories.size() == 1;
            assert level1.child_directories[0] == level2_id;

            let ?level2 = DiodeFileSystem.get_directory(fs, level2_id);
            assert level2.parent_id == ?level1_id;
            assert level2.child_directories.size() == 0;

            // Test get_child_directories functionality
            let root_children = DiodeFileSystem.get_child_directories(fs, DiodeFileSystem.ROOT_DIRECTORY_ID);
            assert root_children.size() == 1;
            assert root_children[0].id == level1_id;

            let level1_children = DiodeFileSystem.get_child_directories(fs, level1_id);
            assert level1_children.size() == 1;
            assert level1_children[0].id == level2_id;

            let level2_children = DiodeFileSystem.get_child_directories(fs, level2_id);
            assert level2_children.size() == 0;

            // Verify directory count
            assert DiodeFileSystem.get_directory_count(fs) == 3; // root + level1 + level2
          },
        );

        await test(
          "Should handle duplicate content in different directories correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory1_id = make_blob(32, 1);
            let directory2_id = make_blob(32, 2);
            let name1 = make_blob(32, 3);
            let name2 = make_blob(32, 4);
            let content_hash = make_blob(32, 5); // Same content hash for both files
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create two directories
            assert isOk(DiodeFileSystem.create_directory(fs, directory1_id, name1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOk(DiodeFileSystem.create_directory(fs, directory2_id, name2, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add file with same content to first directory
            let result1 = DiodeFileSystem.write_file(fs, directory1_id, name1, content_hash, ciphertext);
            assert isOkNat(result1);

            // Add file with same content but different name to second directory
            let result2 = DiodeFileSystem.write_file(fs, directory2_id, name2, content_hash, ciphertext);
            assert isOkNat(result2);

            // Both directories should contain their respective files
            let files1 = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2 = DiodeFileSystem.get_files_in_directory(fs, directory2_id);

            // Both directories should show they contain the file
            assert files1.size() == 1;
            assert files2.size() == 1;

            // Both should reference the same underlying file (content deduplication)
            assert files1[0].content_hash == content_hash;
            // Note: The current implementation reuses the same file record,
            // so they will have the same metadata from the first file
            // This test will fail because files2 will be empty (size 0)
          },
        );

        await test(
          "Should handle explicit delete with content deduplication correctly",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory1_id = make_blob(32, 1);
            let directory2_id = make_blob(32, 2);
            let directory3_id = make_blob(32, 3);
            let name1 = make_blob(32, 4);
            let name2 = make_blob(32, 5);
            let name3 = make_blob(32, 6);
            let content_hash = make_blob(32, 7); // Same content hash for all files
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            // Create three directories
            assert isOk(DiodeFileSystem.create_directory(fs, directory1_id, name1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOk(DiodeFileSystem.create_directory(fs, directory2_id, name2, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOk(DiodeFileSystem.create_directory(fs, directory3_id, name3, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add same content to all three directories
            assert isOkNat(DiodeFileSystem.write_file(fs, directory1_id, name1, content_hash, ciphertext));
            assert isOkNat(DiodeFileSystem.write_file(fs, directory2_id, name2, content_hash, ciphertext));
            assert isOkNat(DiodeFileSystem.write_file(fs, directory3_id, name3, content_hash, ciphertext));

            // Verify all directories contain the file
            let files1_before = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_before = DiodeFileSystem.get_files_in_directory(fs, directory2_id);
            let files3_before = DiodeFileSystem.get_files_in_directory(fs, directory3_id);
            assert files1_before.size() == 1;
            assert files2_before.size() == 1;
            assert files3_before.size() == 1;

            // Verify content is accessible
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
              case (#ok(read_data)) {
                assert read_data == ciphertext;
              };
              case (#err(_)) { assert false };
            };

            // Explicitly delete the file
            switch (DiodeFileSystem.delete_file(fs, files1_before[0].id)) {
              case (#ok()) {};
              case (#err(_)) { assert false };
            };

            // Verify file is removed from ALL directories
            let files1_after = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_after = DiodeFileSystem.get_files_in_directory(fs, directory2_id);
            let files3_after = DiodeFileSystem.get_files_in_directory(fs, directory3_id);
            assert files1_after.size() == 0;
            assert files2_after.size() == 0;
            assert files3_after.size() == 0;

            // Verify content is no longer accessible
            switch (DiodeFileSystem.read_file_chunk(fs, content_hash, 0, 5)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };

            // Verify file is completely gone from the system
            switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
              case (#ok(_)) { assert false };
              case (#err(err)) { assert err == "file not found" };
            };
          },
        );

        await test(
          "Should handle ring buffer cleanup with content deduplication correctly",
          func() : async () {
            // Create filesystem with small capacity to trigger ring buffer cleanup
            let fs = DiodeFileSystem.new(100); // Very small capacity
            let directory1_id = make_blob(32, 1);
            let directory2_id = make_blob(32, 2);
            let name1 = make_blob(32, 3);
            let name2 = make_blob(32, 4);
            let shared_content_hash = make_blob(32, 5);
            let filler_content_hash = make_blob(32, 6);
            let shared_ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);
            // Create large filler content to trigger cleanup (80 bytes + 8 metadata = 88 bytes)
            // Shared content is 5 bytes + 8 metadata = 13 bytes
            // Total would be 101 bytes, exceeding 100 byte capacity
            let filler_ciphertext = Blob.fromArray(Array.tabulate<Nat8>(80, func i = Nat8.fromIntWrap(i + 100)));

            // Create two directories
            assert isOk(DiodeFileSystem.create_directory(fs, directory1_id, name1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOk(DiodeFileSystem.create_directory(fs, directory2_id, name2, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add shared content to both directories
            assert isOkNat(DiodeFileSystem.write_file(fs, directory1_id, name1, shared_content_hash, shared_ciphertext));
            assert isOkNat(DiodeFileSystem.write_file(fs, directory2_id, name2, shared_content_hash, shared_ciphertext));

            // Verify both directories contain the shared file
            let files1_before = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_before = DiodeFileSystem.get_files_in_directory(fs, directory2_id);
            assert files1_before.size() == 1;
            assert files2_before.size() == 1;

            // Verify shared content is accessible
            switch (DiodeFileSystem.read_file_chunk(fs, shared_content_hash, 0, 5)) {
              case (#ok(read_data)) {
                assert read_data == shared_ciphertext;
              };
              case (#err(_)) { assert false };
            };

            // Add large file to trigger ring buffer cleanup of the shared content
            assert isOkNat(DiodeFileSystem.write_file(fs, directory1_id, name1, filler_content_hash, filler_ciphertext));

            // Verify shared file is removed from BOTH directories due to ring buffer cleanup
            let files1_after = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_after = DiodeFileSystem.get_files_in_directory(fs, directory2_id);

            // Find which files remain
            let remaining_files1 = Array.map<DiodeFileSystem.File, Blob>(files1_after, func(f) = f.content_hash);
            let remaining_files2 = Array.map<DiodeFileSystem.File, Blob>(files2_after, func(f) = f.content_hash);

            // Should not contain the shared content hash anymore
            let shared_in_dir1 = Array.find<Blob>(remaining_files1, func(h) = h == shared_content_hash);
            let shared_in_dir2 = Array.find<Blob>(remaining_files2, func(h) = h == shared_content_hash);
            assert shared_in_dir1 == null;
            assert shared_in_dir2 == null;

            // Verify shared content is no longer accessible
            switch (DiodeFileSystem.read_file_chunk(fs, shared_content_hash, 0, 5)) {
              case (#ok(_)) { assert false };
              case (#err(_)) {}; // Expected - file should be gone
            };

            // Verify filler content is still accessible
            switch (DiodeFileSystem.read_file_chunk(fs, filler_content_hash, 0, 10)) {
              case (#ok(_)) {}; // Expected
              case (#err(_)) { assert false };
            };
          },
        );

        await test(
          "Should maintain directory consistency during selective ring buffer cleanup",
          func() : async () {
            // Test that only evicted files are removed, others remain accessible
            let fs = DiodeFileSystem.new(300); // Medium capacity
            let directory1_id = make_blob(32, 1);
            let directory2_id = make_blob(32, 2);
            let name1 = make_blob(32, 3);
            let name2 = make_blob(32, 4);

            // Create different content
            let old_content_hash = make_blob(32, 5);
            let shared_content_hash = make_blob(32, 6);
            let new_content_hash = make_blob(32, 7);

            let old_ciphertext = Blob.fromArray(Array.tabulate<Nat8>(80, func i = Nat8.fromIntWrap(i)));
            let shared_ciphertext = Blob.fromArray(Array.tabulate<Nat8>(80, func i = Nat8.fromIntWrap(i + 50)));
            let new_ciphertext = Blob.fromArray(Array.tabulate<Nat8>(80, func i = Nat8.fromIntWrap(i + 100)));

            // Create directories
            assert isOk(DiodeFileSystem.create_directory(fs, directory1_id, name1, ?DiodeFileSystem.ROOT_DIRECTORY_ID));
            assert isOk(DiodeFileSystem.create_directory(fs, directory2_id, name2, ?DiodeFileSystem.ROOT_DIRECTORY_ID));

            // Add old file to directory1 only
            assert isOkNat(DiodeFileSystem.write_file(fs, directory1_id, name1, old_content_hash, old_ciphertext));

            // Add shared file to both directories
            assert isOkNat(DiodeFileSystem.write_file(fs, directory1_id, name1, shared_content_hash, shared_ciphertext));
            assert isOkNat(DiodeFileSystem.write_file(fs, directory2_id, name2, shared_content_hash, shared_ciphertext));

            // Verify initial state
            let files1_initial = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_initial = DiodeFileSystem.get_files_in_directory(fs, directory2_id);
            assert files1_initial.size() == 2; // old + shared
            assert files2_initial.size() == 1; // shared only

            // Add new large file to trigger cleanup of oldest (old_content)
            assert isOkNat(DiodeFileSystem.write_file(fs, directory2_id, name2, new_content_hash, new_ciphertext));

            // Verify final state
            let files1_final = DiodeFileSystem.get_files_in_directory(fs, directory1_id);
            let files2_final = DiodeFileSystem.get_files_in_directory(fs, directory2_id);

            // Check which content is still accessible
            let old_still_exists = switch (DiodeFileSystem.read_file_chunk(fs, old_content_hash, 0, 10)) {
              case (#ok(_)) { true };
              case (#err(_)) { false };
            };

            let shared_still_exists = switch (DiodeFileSystem.read_file_chunk(fs, shared_content_hash, 0, 10)) {
              case (#ok(_)) { true };
              case (#err(_)) { false };
            };

            let new_still_exists = switch (DiodeFileSystem.read_file_chunk(fs, new_content_hash, 0, 10)) {
              case (#ok(_)) { true };
              case (#err(_)) { false };
            };

            // New content should definitely exist
            assert new_still_exists == true;

            // If old content was evicted, it should be removed from directory1
            // If shared content was evicted, it should be removed from both directories
            // The exact eviction behavior depends on ring buffer implementation,
            // but directories should be consistent with what's actually stored

            if (not old_still_exists) {
              // If old content was evicted, directory1 should not contain it
              let old_in_dir1 = Array.find<DiodeFileSystem.File>(files1_final, func(f) = f.content_hash == old_content_hash);
              assert old_in_dir1 == null;
            };

            if (not shared_still_exists) {
              // If shared content was evicted, neither directory should contain it
              let shared_in_dir1 = Array.find<DiodeFileSystem.File>(files1_final, func(f) = f.content_hash == shared_content_hash);
              let shared_in_dir2 = Array.find<DiodeFileSystem.File>(files2_final, func(f) = f.content_hash == shared_content_hash);
              assert shared_in_dir1 == null;
              assert shared_in_dir2 == null;
            };
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

  private func isOkNat(result : Result.Result<Nat, Text>) : Bool {
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

  private func isOkFile(result : Result.Result<DiodeFileSystem.File, Text>) : Bool {
    switch (result) {
      case (#ok(file)) {
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
