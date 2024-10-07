import Bench "mo:bench";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Iter "mo:base/Iter";
import { DiodeMessages } "../src/";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import WriteableBand "../src/WriteableBand";

module {
  public func init() : Bench.Bench {
    let bench = Bench.Bench();

    bench.name("Diode Messages");
    bench.description("Add items one-by-one");

    bench.rows(["DiodeMessages"]);
    bench.cols(["10", "100", "1000", "10000", "100000", "1000000"]);
    let blob = make_blob(180, 0);

    bench.runner(func(row, col) {
      let ?n = Nat.fromText(col);

      if (row == "DiodeMessages") {
        var dm = DiodeMessages.new();
        for (i in Iter.range(1, n)) {
            let _ = DiodeMessages.add_message(dm, make_key(i % 1000), make_hash(i), blob);
        };

        // for (i in Iter.range(1, n)) {
        //     let msg = DiodeMessages.get_message_by_id(dm, Nat32.fromNat(i));
        //     assert msg.key_id == make_key(i % 100);
        //     assert msg.hash == make_hash(i);
        //     assert msg.ciphertext == make_blob(100, i);
        // };
      };
    });

    bench;
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
