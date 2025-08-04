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
      "Debug Fix",
      func() : async () {

        await test(
          "Debug: Step by step file operations",
          func() : async () {
            let fs = DiodeFileSystem.new(1000);
            let directory_id = make_blob(32, 1);
            let name_hash = make_blob(32, 2);
            let content_hash = make_blob(32, 3);
            let ciphertext = Blob.fromArray([1, 2, 3, 4, 5]);

            Debug.print("=== STEP 1: Create directory ===");
            let dir_result = DiodeFileSystem.create_directory(fs, directory_id, name_hash, null);
            Debug.print("Directory result: " # debug_show (dir_result));

            Debug.print("=== STEP 2: Add file ===");
            let add_result = DiodeFileSystem.add_file(fs, directory_id, name_hash, content_hash, ciphertext);
            Debug.print("Add result: " # debug_show (add_result));

            Debug.print("=== STEP 3: Check file count ===");
            let count = DiodeFileSystem.get_file_count(fs);
            Debug.print("File count: " # debug_show (count));

            Debug.print("=== STEP 4: Check storage usage ===");
            let usage = DiodeFileSystem.get_usage(fs);
            Debug.print("Usage: " # debug_show (usage));

            Debug.print("=== STEP 5: Try to get file by hash ===");
            let get_result = DiodeFileSystem.get_file_by_hash(fs, content_hash);
            Debug.print("Get result: " # debug_show (get_result));

            switch (get_result) {
              case (#ok(file)) {
                Debug.print("SUCCESS: File retrieved!");
                Debug.print("File ID: " # debug_show (file.id));
                Debug.print("File size: " # debug_show (file.size));
                Debug.print("File content hash: " # debug_show (file.content_hash));
                Debug.print("File ciphertext: " # debug_show (file.ciphertext));
              };
              case (#err(err)) {
                Debug.print("ERROR: " # err);
                Debug.print("Let's try to get file by ID directly...");
                let file_by_id = DiodeFileSystem.get_file_by_id(fs, 1);
                Debug.print("File by ID: " # debug_show (file_by_id));
              };
            };
          },
        );
      },
    );
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
};
