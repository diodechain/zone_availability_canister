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
      "Ring Buffer Debug",
      func() : async () {

        await test(
          "Debug: Ring buffer behavior step by step",
          func() : async () {
            let fs = DiodeFileSystem.new(200); // Small storage to trigger ring buffer
            let directory_id = make_blob(32, 1);
            let name_hash1 = make_blob(32, 2);
            let name_hash2 = make_blob(32, 3);
            let name_hash3 = make_blob(32, 4);
            let content_hash1 = make_blob(32, 5);
            let content_hash2 = make_blob(32, 6);
            let content_hash3 = make_blob(32, 7);
            let ciphertext1 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i)));
            let ciphertext2 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 50)));
            let ciphertext3 = Blob.fromArray(Array.tabulate<Nat8>(50, func i = Nat8.fromIntWrap(i + 100)));

            Debug.print("=== STEP 1: Create directory ===");
            assert isOk(DiodeFileSystem.create_directory(fs, directory_id, name_hash1, null));

            Debug.print("=== STEP 2: Add first file ===");
            let add1 = DiodeFileSystem.add_file(fs, directory_id, name_hash1, content_hash1, ciphertext1);
            Debug.print("Add file 1 result: " # debug_show(add1));
            Debug.print("Usage after file 1: " # debug_show(DiodeFileSystem.get_usage(fs)));

            Debug.print("=== STEP 3: Check first file exists ===");
            let get1 = DiodeFileSystem.get_file_by_hash(fs, content_hash1);
            Debug.print("Get file 1 result: " # debug_show(get1));

            Debug.print("=== STEP 4: Add second file ===");
            let add2 = DiodeFileSystem.add_file(fs, directory_id, name_hash2, content_hash2, ciphertext2);
            Debug.print("Add file 2 result: " # debug_show(add2));
            Debug.print("Usage after file 2: " # debug_show(DiodeFileSystem.get_usage(fs)));

            Debug.print("=== STEP 5: Check both files exist ===");
            let get1_after = DiodeFileSystem.get_file_by_hash(fs, content_hash1);
            let get2 = DiodeFileSystem.get_file_by_hash(fs, content_hash2);
            Debug.print("Get file 1 after file 2: " # debug_show(get1_after));
            Debug.print("Get file 2: " # debug_show(get2));

            Debug.print("=== STEP 6: Add third file (should trigger ring buffer) ===");
            let add3 = DiodeFileSystem.add_file(fs, directory_id, name_hash3, content_hash3, ciphertext3);
            Debug.print("Add file 3 result: " # debug_show(add3));
            Debug.print("Usage after file 3: " # debug_show(DiodeFileSystem.get_usage(fs)));

            Debug.print("=== STEP 7: Check ring buffer behavior ===");
            let get1_final = DiodeFileSystem.get_file_by_hash(fs, content_hash1);
            let get2_final = DiodeFileSystem.get_file_by_hash(fs, content_hash2);
            let get3_final = DiodeFileSystem.get_file_by_hash(fs, content_hash3);
            Debug.print("Get file 1 after ring buffer: " # debug_show(get1_final));
            Debug.print("Get file 2 after ring buffer: " # debug_show(get2_final));
            Debug.print("Get file 3 after ring buffer: " # debug_show(get3_final));
          },
        );
      },
    );
  };

  private func isOk(result : Result.Result<(), Text>) : Bool {
    switch (result) {
      case (#ok()) { return true; };
      case (#err(text)) { Debug.print(text); return false; };
    };
  };

  private func isOkNat32(result : Result.Result<Nat32, Text>) : Bool {
    switch (result) {
      case (#ok(n)) { return true; };
      case (#err(text)) { Debug.print(text); return false; };
    };
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
}; 