import { test; suite } "mo:test/async";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import EthRpc "../src/EthRpc";
import Map "mo:map/Map";
import MemberCache "../src/MemberCache";
import MoonbeamZoneMap "../src/MoonbeamZoneMap";
import Oracle "../src/Oracle";
import Types "../src/Types";
import ZoneAvailabilityMigration "../src/ZoneAvailabilityMigration";

persistent actor {
  public shared query func oracle_transform_function(args : Types.TransformArgs) : async Types.HttpResponsePayload {
    Oracle.transform_function(args);
  };

  public func runTests() : async () {
    await suite(
      "EthRpc backend_from_legacy_host",
      func() : async () {
        await test(
          "maps Base host to ChainFusion",
          func() : async () {
            switch (EthRpc.backend_from_legacy_host("mainnet.base.org", "/")) {
              case (#ChainFusion({ network = #BaseMainnet })) {};
              case other {
                Debug.trap("expected ChainFusion, got " # debug_show (other));
              };
            };
          },
        );

        await test(
          "keeps diode host as HttpOutcall",
          func() : async () {
            switch (EthRpc.backend_from_legacy_host("prenet.diode.io:8443", "/")) {
              case (#HttpOutcall({ host; path })) {
                assert host == "prenet.diode.io:8443";
                assert path == "/";
              };
              case other {
                Debug.trap("expected HttpOutcall, got " # debug_show (other));
              };
            };
          },
        );

        await test(
          "backend_to_text",
          func() : async () {
            assert EthRpc.backend_to_text(#ChainFusion({ network = #BaseMainnet })) == "chain-fusion:base";
            assert EthRpc.backend_to_text(#HttpOutcall({ host = "h"; path = "/p" })) == "http:h/p";
          },
        );
      },
    );

    await suite(
      "MoonbeamZoneMap",
      func() : async () {
        await test(
          "maps known moonbeam zone to base",
          func() : async () {
            switch (MoonbeamZoneMap.zone_base("0x05eee5fcecb9074579a575700ae3499a7d109fde")) {
              case (?base) {
                assert base == "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b";
              };
              case null {
                Debug.trap("expected base mapping");
              };
            };
          },
        );

        await test(
          "normalizes case",
          func() : async () {
            switch (MoonbeamZoneMap.zone_base("0x05EEE5FCECB9074579A575700AE3499A7D109FDE")) {
              case (?base) {
                assert base == "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b";
              };
              case null {
                Debug.trap("expected base mapping");
              };
            };
          },
        );

        await test(
          "unknown returns null",
          func() : async () {
            assert MoonbeamZoneMap.zone_base("0x0000000000000000000000000000000000000001") == null;
          },
        );
      },
    );

    await suite(
      "ZoneAvailabilityMigration",
      func() : async () {
        await test(
          "moonbeam zone migrates to base ChainFusion and clears members",
          func() : async () {
            let members = Map.new<Blob, MemberCache.CacheEntry>();
            let key : Blob = "\01\02";
            Map.set(members, Map.bhash, key, { role = 500; identity_contract = null; timestamp = 0 });

            let migrated = ZoneAvailabilityMigration.migrate_cache({
              zone_id = "0x05eee5fcecb9074579a575700ae3499a7d109fde";
              rpc_host = "rpc.api.moonbeam.network";
              rpc_path = "/";
              zone_members = members;
              transform_function = oracle_transform_function;
              call_token = null;
            });

            assert migrated.zone_id == "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b";
            switch (migrated.backend) {
              case (#ChainFusion({ network = #BaseMainnet })) {};
              case other {
                Debug.trap("expected ChainFusion, got " # debug_show (other));
              };
            };
            assert Map.size(migrated.zone_members) == 0;
          },
        );

        await test(
          "base http host becomes ChainFusion and keeps members",
          func() : async () {
            let members = Map.new<Blob, MemberCache.CacheEntry>();
            let key : Blob = "\01\02";
            Map.set(members, Map.bhash, key, { role = 300; identity_contract = null; timestamp = 1 });

            let migrated = ZoneAvailabilityMigration.migrate_cache({
              zone_id = "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b";
              rpc_host = "mainnet.base.org";
              rpc_path = "/";
              zone_members = members;
              transform_function = oracle_transform_function;
              call_token = null;
            });

            assert migrated.zone_id == "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b";
            switch (migrated.backend) {
              case (#ChainFusion({ network = #BaseMainnet })) {};
              case other {
                Debug.trap("expected ChainFusion, got " # debug_show (other));
              };
            };
            assert Map.size(migrated.zone_members) == 1;
          },
        );

        await test(
          "diode host stays HttpOutcall",
          func() : async () {
            let migrated = ZoneAvailabilityMigration.migrate_cache({
              zone_id = "0xe18cbbd6bd2babd532b297022533bdb00251ed58";
              rpc_host = "prenet.diode.io:8443";
              rpc_path = "/";
              zone_members = Map.new();
              transform_function = oracle_transform_function;
              call_token = null;
            });

            switch (migrated.backend) {
              case (#HttpOutcall({ host; path })) {
                assert host == "prenet.diode.io:8443";
                assert path == "/";
              };
              case other {
                Debug.trap("expected HttpOutcall, got " # debug_show (other));
              };
            };
          },
        );
      },
    );
  };
};
