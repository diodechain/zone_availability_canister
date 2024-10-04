import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import {test; suite} "mo:test/async";
import { DiodeMessages } "../src/";
import Result "mo:base/Result";

actor {
  public func runTests() : async () {
    var dm = DiodeMessages.new();

    await suite("Add Message", func() : async () {
      await test("Should fail adding message to inbox", func() : async () {
        assert Result.isErr(DiodeMessages.add_message(dm, "key_id", "hash", "ciphertext"));
      });

      await test("Should add one message to inbox", func() : async () {
        assert isOk(DiodeMessages.add_message(dm, make_key(1), make_hash(1), "cipertext 1"));

        let message1 = DiodeMessages.get_message_by_id(dm, 1);
        assert message1.id == 1;
        assert message1.key_id == make_key(1);
        assert message1.hash == make_hash(1);
        assert message1.ciphertext == "cipertext 1";

        let ?message1h = DiodeMessages.get_message_by_hash(dm, make_hash(1));
        assert message1h == message1;

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(1))) == ?1;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(1))) == ?1;

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(2))) == null;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(2))) == null;
      });

      await test("Should add two messages to inbox", func() : async () {
        assert isOk(DiodeMessages.add_message(dm, make_key(1), make_hash(1), "cipertext 1"));

        let message1 = DiodeMessages.get_message_by_id(dm, 1);
        assert message1.id == 1;
        assert message1.key_id == make_key(1);
        assert message1.hash == make_hash(1);
        assert message1.ciphertext == "cipertext 1";
        assert message1.prev_msg_id == 0;
        assert message1.next_msg_id == 0;

        let ?message1h = DiodeMessages.get_message_by_hash(dm, make_hash(1));
        assert message1h == message1;
        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(1))) == ?1;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(1))) == ?1;
        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(2))) == null;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(2))) == null;
        assert isOk(DiodeMessages.add_message(dm, make_key(1), make_hash(2), "cipertext 2"));

        let message2 = DiodeMessages.get_message_by_id(dm, 2);
        assert message2.id == 2;
        assert message2.key_id == make_key(1);
        assert message2.hash == make_hash(2);
        assert message2.ciphertext == "cipertext 2";
        assert message2.prev_msg_id == 1;
        assert message2.next_msg_id == 0;

        let ?message2h = DiodeMessages.get_message_by_hash(dm, make_hash(2));
        assert message2h == message2;

        let message1b = DiodeMessages.get_message_by_id(dm, 1);
        assert message1b.next_msg_id == 2;

        assert (DiodeMessages.get_min_message_id_by_key(dm, make_key(1))) == ?1;
        assert (DiodeMessages.get_max_message_id_by_key(dm, make_key(1))) == ?2;
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
