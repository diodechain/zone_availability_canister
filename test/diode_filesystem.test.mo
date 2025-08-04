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

// Execute tests directly
let _ = do {
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
          assert fs.next_entry_offset == ?0; // Fixed: constructor sets this to ?0, not null
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
          let parent_directory_id = make_blob(32, 1);
          let parent_name_hash = make_blob(32, 2);
          let child_directory_id = make_blob(32, 3);
          let child_name_hash = make_blob(32, 4);

          // Create parent directory
          assert isOk(DiodeFileSystem.create_directory(fs, parent_directory_id, parent_name_hash, null));

          // Create child directory
          assert isOk(DiodeFileSystem.create_directory(fs, child_directory_id, child_name_hash, ?parent_directory_id));

          let ?parent_directory = DiodeFileSystem.get_directory(fs, parent_directory_id);
          assert parent_directory.child_directories.size() == 1;
          assert parent_directory.child_directories[0] == child_directory_id;

          let ?child_directory = DiodeFileSystem.get_directory(fs, child_directory_id);
          assert child_directory.parent_id == ?parent_directory_id;
        },
      );

      await test(
        "Should fail creating directory with invalid parameters",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);

          // Test invalid directory_id size
          switch (DiodeFileSystem.create_directory(fs, make_blob(31, 1), make_blob(32, 2), null)) {
            case (#ok()) { assert false; };
            case (#err(err)) { assert err == "directory_id must be 32 bytes"; };
          };

          // Test invalid name_hash size
          switch (DiodeFileSystem.create_directory(fs, make_blob(32, 1), make_blob(31, 2), null)) {
            case (#ok()) { assert false; };
            case (#err(err)) { assert err == "name_hash must be 32 bytes"; };
          };

          // Test duplicate directory
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));
          switch (DiodeFileSystem.create_directory(fs, directory_id, name_hash, null)) {
            case (#ok()) { assert false; };
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

          // Create directory first
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Add file to directory
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5)) {
            case (#ok(file_id)) {
              assert file_id == 1;
            };
            case (#err(_)) { assert false; };
          };

          // Verify file exists
          switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
            case (#ok(file)) {
              assert file.directory_id == directory_id;
              assert file.name_hash == name_hash;
              assert file.content_hash == content_hash;
              assert file.size == 5;
              assert file.finalized == false;
            };
            case (#err(_)) { assert false; };
          };
        },
      );

      await test(
        "Should add multiple files to directory",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);

          // Create directory first
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Add multiple files
          let content_hash1 = make_blob(32, 3);
          let content_hash2 = make_blob(32, 4);
          let content_hash3 = make_blob(32, 5);

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash1, 10)) {
            case (#ok(file_id)) { assert file_id == 1; };
            case (#err(_)) { assert false; };
          };

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash2, 20)) {
            case (#ok(file_id)) { assert file_id == 2; };
            case (#err(_)) { assert false; };
          };

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash3, 30)) {
            case (#ok(file_id)) { assert file_id == 3; };
            case (#err(_)) { assert false; };
          };

          // Check file index has increased
          assert fs.file_index == 4;

          // Verify all files exist
          assert Result.isOk(DiodeFileSystem.get_file_by_hash(fs, content_hash1));
          assert Result.isOk(DiodeFileSystem.get_file_by_hash(fs, content_hash2));
          assert Result.isOk(DiodeFileSystem.get_file_by_hash(fs, content_hash3));
        },
      );

      await test(
        "Should fail adding file with invalid parameters",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory first
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Test invalid directory_id size
          switch (DiodeFileSystem.allocate_file(fs, make_blob(31, 1), name_hash, content_hash, 5)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "directory_id must be 32 bytes"; };
          };

          // Test invalid name_hash size
          switch (DiodeFileSystem.allocate_file(fs, directory_id, make_blob(31, 2), content_hash, 5)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "name_hash must be 32 bytes"; };
          };

          // Test invalid content_hash size
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, make_blob(31, 3), 5)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "content_hash must be 32 bytes"; };
          };

          // Test non-existent directory
          let non_existent_directory = make_blob(32, 99);
          switch (DiodeFileSystem.allocate_file(fs, non_existent_directory, name_hash, content_hash, 5)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "directory not found"; };
          };
        },
      );

      await test(
        "Should handle ring-buffer behavior correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(200); // Small storage limit
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);

          // Create directory
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Add files until we exceed storage
          let content_hash1 = make_blob(32, 3);
          let content_hash2 = make_blob(32, 4);
          let content_hash3 = make_blob(32, 5);

          // These files should fit
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash1, 50)) {
            case (#ok(file_id)) { assert file_id == 1; };
            case (#err(_)) { assert false; };
          };

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash2, 50)) {
            case (#ok(file_id)) { assert file_id == 2; };
            case (#err(_)) { assert false; };
          };

          // This file should still fit
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash3, 50)) {
            case (#ok(file_id)) { assert file_id == 3; };
            case (#err(_)) { assert false; };
          };

          // Check storage usage
          assert fs.current_storage > 0;

          // Now add a large file that should trigger ring buffer behavior
          let content_hash4 = make_blob(32, 6);
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash4, 150)) {
            case (#ok(file_id)) { assert file_id == 4; };
            case (#err(_)) { assert false; };
          };

          // Some older files might have been evicted
          // But the newest file should exist
          assert Result.isOk(DiodeFileSystem.get_file_by_hash(fs, content_hash4));
        },
      );

      await test(
        "Should handle duplicate file content correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Add file
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 10)) {
            case (#ok(file_id)) { assert file_id == 1; };
            case (#err(_)) { assert false; };
          };

          // Try to add same file again
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 10)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "file already exists"; };
          };
        },
      );

      await test(
        "Should get files by ID correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory and file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 15)) {
            case (#ok(file_id)) {
              assert file_id == 1;

              // Get file by ID
              let ?file = DiodeFileSystem.get_file_by_id(fs, file_id);
              assert file.id == file_id;
              assert file.content_hash == content_hash;
              assert file.size == 15;
            };
            case (#err(_)) { assert false; };
          };

          // Try to get non-existent file
          let ?non_existent = DiodeFileSystem.get_file_by_id(fs, 999);
          assert false; // Should be null
        },
      );

      await test(
        "Should handle empty directory correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);

          // Create empty directory
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Get files in empty directory
          let files = DiodeFileSystem.get_files_in_directory(fs, directory_id);
          assert files.size() == 0;
        },
      );

      await test(
        "Should handle usage statistics correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);

          // Initially should be empty
          assert fs.current_storage == 0;
          assert fs.max_storage == 1000;

          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory and file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 100)) {
            case (#ok(_)) {
              // Storage should have increased
              assert fs.current_storage > 0;
            };
            case (#err(_)) { assert false; };
          };
        },
      );

      await test(
        "Should handle set_max_storage correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          assert fs.max_storage == 1000;

          DiodeFileSystem.set_max_storage(fs, 2000);
          assert fs.max_storage == 2000;
        },
      );

      await test(
        "Should handle chunked file upload correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Allocate file for chunked upload
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 100)) {
            case (#ok(file_id)) {
              assert file_id == 1;

              // Write chunks
              let chunk1 = make_blob(20, 1);
              let chunk2 = make_blob(30, 2);
              let chunk3 = make_blob(50, 3);

              switch (DiodeFileSystem.write_chunk(fs, file_id, 0, chunk1)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              switch (DiodeFileSystem.write_chunk(fs, file_id, 20, chunk2)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              switch (DiodeFileSystem.write_chunk(fs, file_id, 50, chunk3)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Finalize file
              switch (DiodeFileSystem.finalize_file(fs, file_id)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Check file is finalized
              switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
                case (#ok(file)) {
                  assert file.finalized == true;
                };
                case (#err(_)) { assert false; };
              };
            };
            case (#err(_)) { assert false; };
          };
        },
      );

      await test(
        "Should handle chunked file download correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory and allocate file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 100)) {
            case (#ok(file_id)) {
              // Write some data
              let chunk = make_blob(100, 42);
              switch (DiodeFileSystem.write_chunk(fs, file_id, 0, chunk)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              switch (DiodeFileSystem.finalize_file(fs, file_id)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Read chunks back
              switch (DiodeFileSystem.read_chunk(fs, file_id, 0, 50)) {
                case (#ok(data)) {
                  assert data.size() == 50;
                };
                case (#err(_)) { assert false; };
              };

              switch (DiodeFileSystem.read_chunk(fs, file_id, 50, 50)) {
                case (#ok(data)) {
                  assert data.size() == 50;
                };
                case (#err(_)) { assert false; };
              };
            };
            case (#err(_)) { assert false; };
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

          // Create directory and allocate file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 50)) {
            case (#ok(file_id)) {
              // Try to write chunk beyond file size
              let large_chunk = make_blob(100, 1);
              switch (DiodeFileSystem.write_chunk(fs, file_id, 0, large_chunk)) {
                case (#ok()) { assert false; };
                case (#err(err)) { assert err == "chunk exceeds file size"; };
              };

              // Try to write chunk at invalid offset
              let chunk = make_blob(10, 1);
              switch (DiodeFileSystem.write_chunk(fs, file_id, 100, chunk)) {
                case (#ok()) { assert false; };
                case (#err(err)) { assert err == "offset exceeds file size"; };
              };

              // Try to write to non-existent file
              switch (DiodeFileSystem.write_chunk(fs, 999, 0, chunk)) {
                case (#ok()) { assert false; };
                case (#err(err)) { assert err == "file not found"; };
              };
            };
            case (#err(_)) { assert false; };
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
          let file_data = make_blob(50, 42);

          // Create directory
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Write file directly
          switch (DiodeFileSystem.write_file(fs, directory_id, name_hash, content_hash, file_data)) {
            case (#ok(file_id)) {
              assert file_id == 1;

              // Verify file exists and is finalized
              switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
                case (#ok(file)) {
                  assert file.finalized == true;
                  assert file.size == 50;
                };
                case (#err(_)) { assert false; };
              };

              // Should be able to read the data back
              switch (DiodeFileSystem.read_chunk(fs, file_id, 0, 50)) {
                case (#ok(data)) {
                  assert data.size() == 50;
                };
                case (#err(_)) { assert false; };
              };
            };
            case (#err(_)) { assert false; };
          };
        },
      );

      await test(
        "Should handle finalize_file idempotently",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory and allocate file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 50)) {
            case (#ok(file_id)) {
              // Write some data
              let chunk = make_blob(50, 1);
              switch (DiodeFileSystem.write_chunk(fs, file_id, 0, chunk)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Finalize once
              switch (DiodeFileSystem.finalize_file(fs, file_id)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Finalize again should be idempotent
              switch (DiodeFileSystem.finalize_file(fs, file_id)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // File should still be finalized
              switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
                case (#ok(file)) {
                  assert file.finalized == true;
                };
                case (#err(_)) { assert false; };
              };
            };
            case (#err(_)) { assert false; };
          };
        },
      );

      await test(
        "Should handle delete_file correctly",
        func() : async () {
          let fs = DiodeFileSystem.new(1000);
          let directory_id = make_blob(32, 1);
          let name_hash = make_blob(32, 2);
          let content_hash = make_blob(32, 3);

          // Create directory and file
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 50)) {
            case (#ok(file_id)) {
              // Write and finalize file
              let chunk = make_blob(50, 1);
              switch (DiodeFileSystem.write_chunk(fs, file_id, 0, chunk)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              switch (DiodeFileSystem.finalize_file(fs, file_id)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Verify file exists before deletion
              assert Result.isOk(DiodeFileSystem.get_file_by_hash(fs, content_hash));

              // Delete file
              switch (DiodeFileSystem.delete_file(fs, content_hash)) {
                case (#ok()) {};
                case (#err(_)) { assert false; };
              };

              // Verify file no longer exists
              switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
                case (#ok(_)) { assert false; };
                case (#err(err)) { assert err == "file not found"; };
              };
            };
            case (#err(_)) { assert false; };
          };

          // Try to delete non-existent file
          switch (DiodeFileSystem.delete_file(fs, content_hash)) {
            case (#ok()) { assert false; };
            case (#err(err)) { assert err == "file not found"; };
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
          assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash, null));

          // Allocate file but don't finalize
          switch (DiodeFileSystem.allocate_file(fs, directory_id, name_hash, content_hash, 5)) {
            case (#ok(file_id)) {
              assert file_id == 1;
            };
            case (#err(_)) { assert false; };
          };

          // Verify file exists but not finalized
          switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
            case (#ok(file)) {
              assert file.finalized == false;
            };
            case (#err(_)) { assert false; };
          };

          // Directory should not contain the file (not finalized)
          let files_before = DiodeFileSystem.get_files_in_directory(fs, directory_id);
          assert files_before.size() == 0;

          // Delete the unfinalized file
          switch (DiodeFileSystem.delete_file(fs, content_hash)) {
            case (#ok()) {};
            case (#err(_)) { assert false; };
          };

          // Verify file no longer exists
          switch (DiodeFileSystem.get_file_by_hash(fs, content_hash)) {
            case (#ok(_)) { assert false; };
            case (#err(err)) { assert err == "file not found"; };
          };

          // Directory should still be empty
          let files_after = DiodeFileSystem.get_files_in_directory(fs, directory_id);
          assert files_after.size() == 0;
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
