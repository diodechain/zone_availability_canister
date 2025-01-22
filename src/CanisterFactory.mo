import {endsWith; size} "mo:base/Text";
import {ic} "mo:ic";
import {trap} "mo:base/Debug";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import CyclesManager "mo:cycles-manager/CyclesManager";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import ZoneAvailabilityCanister "ZoneAvailabilityCanister";

// A simple battery canister actor example that implements the cycles_manager_transferCycles API of the CyclesManager.Interface 

actor CanisterFactory {
  // Initializes a cycles manager
  stable let cyclesManager = CyclesManager.init({
    // By default, with each transfer request 500 billion cycles will be transferred
    // to the requesting canister, provided they are permitted to request cycles
    //
    // This means that if a canister is added with no quota, it will default to the quota of #fixedAmount(500)
    defaultCyclesSettings = {
      quota = #fixedAmount(500_000_000_000);
    };
    // Allow an aggregate of 1 trillion cycles to be transferred every 24 hours (~1.30 USD)
    aggregateSettings = {
      quota = #rate({
        maxAmount = 1_000_000_000_000;
        durationInSeconds = 24 * 60 * 60;
      });
    };
    // 50 billion is a good default minimum for most low use canisters
    minCyclesPerTopup = ?50_000_000_000;
  });

  // @required - IMPORTANT!!!
  // Allows canisters to request cycles from this "battery canister" that implements
  // the cycles manager
  public shared ({ caller }) func cycles_manager_transferCycles(
    cyclesRequested: Nat
  ): async CyclesManager.TransferCyclesResult {
    if (not isCanister(caller)) trap("Calling principal must be a canister");
    
    let result = await* CyclesManager.transferCycles({
      cyclesManager;
      canister = caller;
      cyclesRequested;
    });
    result;
  };

  // Creating a new zone availability canister
  // This adds a canister with a 1 trillion cycles allowed per 24 hours cycles quota
  public shared func create_zone_availability_canister(
    zone_id : Text,
    rpc_host : Text,
    rpc_path : Text
  ) : async Principal {

    // 1 trillion cycles is ~ 1.30 USD
    Cycles.add<system>(1_000_000_000_000);
    let canister = await ZoneAvailabilityCanister.ZoneAvailabilityCanister({
      zone_id;
      rpc_host;
      rpc_path;
      cycles_requester_id = Principal.fromActor(CanisterFactory);
    });

    let principal = Principal.fromActor(canister);

    CyclesManager.addChildCanister(cyclesManager, principal, {
      // This topup rule allows 1 Trillion cycles every 24 hours
      quota = ?(#rate({
        maxAmount = 1_000_000_000_000;
        durationInSeconds = 24 * 60 * 60;
      }));
    });

    principal;
  };


  func isCanister(p : Principal) : Bool {
    let principal_text = Principal.toText(p);
    // Canister principals have 27 characters
    size(principal_text) == 27
    and
    // Canister principals end with "-cai"
    endsWith(principal_text, #text "-cai");
  };

  public query func get_cycles_balance() : async Nat {
    Cycles.balance();
  };

  public shared({ caller }) func install_code(canisterId: Principal, wasmModule: Blob, arg : Blob): async() {
      if (not isAdmin(caller)) {
          throw Error.reject("Unauthorized access. Caller is not an admin.");
      };

      await ic.install_code({
        canister_id = canisterId;
        arg = arg;
        wasm_module = wasmModule;
        mode = #reinstall;
        sender_canister_version = null;
      });
  };

  func isAdmin(p : Principal) : Bool {
    p == Principal.fromText("mnkyz-mnbtr-dsmec-2mbve-2yktb-kaktp-jpw52-vjbxb-dzdjm-4rglf-uqe");
  };
}
