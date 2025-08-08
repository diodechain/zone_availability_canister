import { ic } "IC";
import Cycles "mo:base/ExperimentalCycles";

persistent actor TestCanister {
  public shared func test_record_output() : async ((Nat32, Nat32)) {
    (0, 1);
  };

  public shared func test_record_input(record : (Nat32, Nat32)) : async Nat32 {
    let (a, b) = record;
    a + b;
  };
  
  public query func get_cycles_balance() : async Nat {
    Cycles.balance();
  };

  public shared func get_stable_size() : async Nat32 {
    await ic.stable_size();
  };

  public shared func get_stable64_size() : async Nat64 {
    await ic.stable64_size();
  };
};
