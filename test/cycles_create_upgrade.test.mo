import { test; suite } "mo:test/async";
import Debug "mo:base/Debug";
import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import ZoneAvailabilityCanister "../src/ZoneAvailabilityCanister";
import IC "../src/IC";

/// Cycle consumption for ZAC creation using the same path as
/// CanisterFactory.create_zone_availability_canister
/// (`await (with cycles = 1.5T) ZoneAvailabilityCanister(...)`).
///
/// Upgrade figures (factory upgrade_code: stop + #upgrade #keep + start) are
/// measured by `test/cycles_create_upgrade.py` (v414 → v415 under PocketIC).
///
/// Run both: `python3 test/cycles_create_upgrade.py`
persistent actor Self {
  let create_cycles : Nat = 1_500_000_000_000;

  public func runTests() : async () {
    await suite(
      "ZAC cycle consumption",
      func() : async () {
        await test(
          "create_zone_availability_canister cycle figures",
          func() : async () {
            let self = Principal.fromActor(Self);
            await IC.ic.provisional_top_up_canister({
              canister_id = self;
              amount = 10_000_000_000_000;
            });

            let before = Cycles.balance();
            assert before >= create_cycles;

            let canister = await (with cycles = create_cycles) ZoneAvailabilityCanister.ZoneAvailabilityCanister({
              zone_id = "0xcd0afb71cb7ea9d16c719869682a399428eec34a";
              rpc_host = "mainnet.base.org";
              rpc_path = "/";
              cycles_requester_id = self;
              call_token = null;
            });

            let after = Cycles.balance();
            let child_balance = await canister.get_cycles_balance();
            let factory_spent = before - after;
            let overhead = factory_spent - child_balance;

            Debug.print("CREATE factory_spent=" # Nat.toText(factory_spent));
            Debug.print("CREATE child_balance=" # Nat.toText(child_balance));
            Debug.print("CREATE overhead=" # Nat.toText(overhead));
            Debug.print("CREATE attach_burn=" # Nat.toText(create_cycles - child_balance));
            Debug.print("CREATE factory_call_cost=" # Nat.toText(factory_spent - create_cycles));

            assert factory_spent >= create_cycles;
            assert child_balance > 0;
            assert overhead > 0;
            assert overhead < create_cycles;
            assert child_balance + overhead == factory_spent;
            assert (await canister.get_version()) == 415;
          },
        );
      },
    );
  };
};
