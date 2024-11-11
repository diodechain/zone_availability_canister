import {test; suite} "mo:test/async";
import Oracle "../src/Oracle";
import Debug "mo:base/Debug";
actor {
  public func runTests() : async () {
    await suite("Get Zone Members", func() : async () {
      await test("Should get zone members", func() : async () {
        Debug.print("Getting zone members");
        let members = await Oracle.get_zone_members("0xe18cbbd6bd2babd532b297022533bdb00251ed58", "prenet.diode.io", ":8445/");
        Debug.print(debug_show(members));
        assert members.size() != 0;
      });
    });
  };
};