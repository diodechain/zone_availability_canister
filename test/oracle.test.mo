import {test; suite} "mo:test/async";
import Debug "mo:base/Debug";
import Oracle "../src/Oracle";
import Types "../src/Types";

actor {
  public shared query func oracle_transform_function(args : Types.TransformArgs) : async Types.HttpResponsePayload {
    Oracle.transform_function(args);
  };

  public func runTests() : async () {
    await suite("Get Zone Members", func() : async () {
      await test("Should get zone member role", func() : async () {
        Debug.print("Getting zone member role");
        let context : Oracle.Context = {
          rpc_host = "prenet.diode.io:8443";
          rpc_path = "/";
          transform_function = oracle_transform_function;
        };
        let role = await Oracle.get_zone_member_role(context, "0xe18cbbd6bd2babd532b297022533bdb00251ed58", "065f5e25d9689260c949d796ba6a580dbe6dc2cd");
        Debug.print(debug_show(role));
        assert role != 0;
      });
    });
  };
};