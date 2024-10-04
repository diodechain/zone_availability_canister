import Bench "mo:bench";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Region "mo:base/Region";

module {
  public func init() : Bench.Bench {
    let bench = Bench.Bench();

    bench.name("Test the regions");
    bench.rows(["Regions"]);
    bench.cols(["1", "10", "100", "1000", "10000"]);

    bench.runner(func(row, col) {
      let ?n = Nat.fromText(col);
      
      for (i in Iter.range(0, n - 1)) {
        var reg = Region.new();
        let _ = Region.grow(reg, 1);
        assert Region.size(reg) == 1;
        Region.storeBlob(reg, 0, make_blob(100, i));
      };
    });

    bench;
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
};
