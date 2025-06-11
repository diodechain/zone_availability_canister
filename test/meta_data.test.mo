import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import {test; suite} "mo:test/async";
import { MetaData } "../src/";

actor {
  public func runTests() : async () {
    var md = MetaData.new();
    MetaData.set_public_and_protected_key(md, make_key(1), make_key(2));

    await suite("Add Data", func() : async () {
      await test("Should add one data entry", func() : async () {
        let info = MetaData.get_meta_data_info(md);
        assert info.public_key == ?make_key(1);
        assert info.vet_protected_key == ?make_key(2);
        assert info.manifest == 0;
        assert info.timestamp == 0;

        assert (MetaData.get_data_entry(md, 1)) == null;

        MetaData.set_data_entry(md, 1, "data 1");

        let data1 = MetaData.get_data_entry(md, 1);

        switch (data1) {
          case (null) {
            assert false;
          };
          case (?data) {
            assert data.data == "data 1";

            let info2 = MetaData.get_meta_data_info(md);
            assert info2.public_key == ?make_key(1);
            assert info2.vet_protected_key == ?make_key(2);
            assert info2.manifest == 2;
            assert info2.timestamp == data.timestamp;
            assert info2.timestamp > 0;

            assert (MetaData.get_data_entry(md, 1)) == data1;
            assert (MetaData.get_data_entry(md, 2)) == null;
          };
        };

        MetaData.set_data_entry(md, 2, "data 2");
        let info3 = MetaData.get_meta_data_info(md);
        assert info3.manifest == 6;
        let timestamps = MetaData.get_timestamps(md);
        assert timestamps.size() == 2;
        assert timestamps[0].key == 1;
        assert timestamps[1].key == 2;

        MetaData.delete_data_entry(md, 1);
        let info4 = MetaData.get_meta_data_info(md);
        assert info4.manifest == 4;
        assert (MetaData.get_data_entry(md, 1)) == null;
      });
    });
  };


  private func make_key(n : Nat) : Blob {
    return make_blob(41, n);
  };

  private func make_blob(size : Nat, n : Nat) : Blob {
    let a = Array.tabulate<Nat8>(size, func i = Nat8.fromIntWrap(Nat.bitshiftRight(n, 8 * Nat32.fromIntWrap(i))));
    return Blob.fromArray(a);
  };
};
