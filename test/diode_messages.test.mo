import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import {test; suite} "mo:test";
import { DiodeMessages } "../src/";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";

module {
  public func runTests() : async () {
    var dm = DiodeMessages.new();

    suite("Add Message", func() {
      test("Should fail adding message to inbox", func() {
        assert Result.isErr(DiodeMessages.add_message(dm, "key_id", "hash", "ciphertext"));
      });

      test("Should add message to inbox", func() {
        assert isOk(DiodeMessages.add_message(dm, make_key(1), make_hash(1), "cipertext 1"));

        let message = DiodeMessages.get_message_by_id(dm, 0);
        assert message.key_id == make_key(1);
        assert message.hash == make_hash(1);
        assert message.ciphertext == "cipertext 1";

        let ?message2 = DiodeMessages.get_message_by_hash(dm, make_hash(1));
        assert message2.key_id == make_key(1);
        assert message2.hash == make_hash(1);
        assert message2.ciphertext == "cipertext 1";

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(1))) == ?0;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(1))) == ?0;
        assert (DiodeMessages.get_idx_message_id_by_key(dm, make_key(1), 0)) == ?0;
        assert (DiodeMessages.get_idx_message_id_by_key(dm, make_key(1), 1)) == null;

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(2))) == null;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(2))) == null;
        assert (DiodeMessages.get_idx_message_id_by_key(dm, make_key(2), 0)) == null;

        assert isOk(DiodeMessages.add_message(dm, make_key(1), make_hash(2), "cipertext 2"));

        let message3 = DiodeMessages.get_message_by_id(dm, 1);
        assert message3.key_id == make_key(1);
        assert message3.hash == make_hash(2);
        assert message3.ciphertext == "cipertext 2";

        let ?message4 = DiodeMessages.get_message_by_hash(dm, make_hash(2));
        assert message4.key_id == make_key(1);
        assert message4.hash == make_hash(2);
        assert message4.ciphertext == "cipertext 2";

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(1))) == ?0;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(1))) == ?1;
        assert (DiodeMessages.get_idx_message_id_by_key(dm, make_key(1), 0)) == ?0;
        assert (DiodeMessages.get_idx_message_id_by_key(dm, make_key(1), 1)) == ?1;
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
