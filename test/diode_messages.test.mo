import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import {test; suite; skip} "mo:test/async";
import { DiodeMessages } "../src/";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
actor {
  public func runTests() : async () {
    ExperimentalCycles.add<system>(1_000_000_000_000);

    var diode_messages = await DiodeMessages();

    await suite("Add Message", func() : async () {
      await test("Should fail adding message to inbox", func() : async () {
        assert Result.isErr(await diode_messages.add_message("key_id", "hash", "ciphertext"));
      });

      await test("Should add message to inbox", func() : async () {
        assert isOk(await diode_messages.add_message(make_key(1), make_hash(1), "cipertext 1"));

        // let message = await diode_messages.get_message_by_id(0);
        // assert message.key_id == make_key(1);
        // assert message.hash == make_hash(1);
        // assert message.ciphertext == "cipertext 1";
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

  private func make_key(n : Nat) : Blob {
    return make_blob(24, n);
  };

  private func make_hash(n : Nat) : Blob {
    return make_blob(32, n);
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
};
