import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import CyclesManager "mo:cycles-manager/CyclesManager";
import CyclesRequester "mo:cycles-manager/CyclesRequester";
import Debug "mo:base/Debug";
import DiodeMessages "./DiodeMessages";
import MemberCache "./MemberCache";
import Nat32 "mo:base/Nat32";
import Oracle "./Oracle";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Sha256 "mo:sha2/Sha256";
import Types "./Types";
import Time "mo:base/Time";
import {ic} "./IC";
import Prim "mo:⛔";

shared (_init_msg) actor class ZoneAvailabilityCanister(
  _args : {
    zone_id : Text;
    rpc_host : Text;
    rpc_path : Text;
    cycles_requester_id : Principal;
  }
) = this {
  public shared query func oracle_transform_function(args : Types.TransformArgs) : async Types.HttpResponsePayload {
    Oracle.transform_function(args);
  };

  stable var dm : DiodeMessages.MessageStore = DiodeMessages.new();
  stable var zone_members : MemberCache.Cache = MemberCache.new(_args. zone_id, _args.rpc_host, _args.rpc_path, oracle_transform_function);
  stable var installation_id : Int = Time.now();

  // Topup rule based on https://cycleops.notion.site/Best-Practices-for-Top-up-Rules-e3e9458ec96f46129533f58016f66f6e
  // When below .7 trillion cycles, topup by .5 trillion (~65 cents)
  stable var cycles_requester: CyclesRequester.CyclesRequester = CyclesRequester.init({
    batteryCanisterPrincipal = _args.cycles_requester_id;
    topupRule = {
      threshold = 700_000_000_000;
      method = #by_amount(500_000_000_000);
    };
  });

  public query func get_zone_id() : async Text {
    zone_members.zone_id;
  };

  public shared(msg) func add_message(key_id : Blob, ciphertext : Blob) : async Result.Result<Nat32, Text> {
    ignore await* request_topup_if_low();
    assert_membership(msg.caller);

    let hash = Sha256.fromBlob(#sha256, ciphertext);
    DiodeMessages.add_message(dm, key_id, hash, ciphertext);
  };

  public shared(msg) func add_messages(messages : [(Blob, Blob)]) : async Result.Result<[Nat32], Text> {
    ignore await* request_topup_if_low();
    assert_membership(msg.caller);
    var message_ids : [Nat32] = [];

    for ((key_id, ciphertext) in messages.vals()) {
      let hash = Sha256.fromBlob(#sha256, ciphertext);
      switch (DiodeMessages.add_message(dm, key_id, hash, ciphertext)) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok(message_id)) {
          message_ids := Array.append(message_ids, [message_id]);
        };
      };
    };
    #ok(message_ids);
  };

  public query(msg) func get_message_by_hash(message_hash : Blob) : async ?DiodeMessages.Message {
    assert_membership(msg.caller);
    DiodeMessages.get_message_by_hash(dm, message_hash);
  };

  public query(msg) func get_message_by_id(message_id : Nat32) : async DiodeMessages.Message {
    assert_membership(msg.caller);
    DiodeMessages.get_message_by_id(dm, message_id);
  };

  public query(msg) func get_messages_by_range(min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
    assert_membership(msg.caller);
    DiodeMessages.get_messages_by_range(dm, min_message_id, max_message_id);
  };

  public shared query func get_min_message_id() : async Nat32 {
    DiodeMessages.get_min_message_id(dm);
  };

  public shared query func get_max_message_id() : async Nat32 {
    DiodeMessages.get_max_message_id(dm);
  };

  public shared query func get_min_message_id_by_key(key_id : Blob) : async ?Nat32 {
    DiodeMessages.get_min_message_id_by_key(dm, key_id);
  };

  public shared query func get_max_message_id_by_key(key_id : Blob) : async ?Nat32 {
    DiodeMessages.get_max_message_id_by_key(dm, key_id);
  };

  public query(msg) func get_messages_by_range_for_key(key_id : Blob, min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
    assert_membership(msg.caller);
    DiodeMessages.get_messages_by_range_for_key(dm, key_id, min_message_id, max_message_id);
  };

  public query(msg) func my_role() : async Nat {
    MemberCache.get_role(zone_members, msg.caller);
  };

  public shared query func get_role(member : Principal) : async Nat {
    MemberCache.get_role(zone_members, member);
  };

  public func update_role(public_key : Blob) : async Nat {
    ignore await* request_topup_if_low();
    await MemberCache.update_member(zone_members, public_key);
  };

  public func update_identity_role(public_key : Blob, identity_contract_address : Blob) : async Nat {
    ignore await* request_topup_if_low();
    await MemberCache.update_identity_member(zone_members, public_key, identity_contract_address);
  };

  func assert_membership(member : Principal) {
    let role = MemberCache.get_role(zone_members, member);
    if (role == 0) {
      Debug.trap("Not a member of the zone");
    };
  };

  // From https://github.com/CycleOperators/cycles-manager/blob/main/example/Child.mo
  func request_topup_if_low(): async* CyclesManager.TransferCyclesResult {
    await* CyclesRequester.requestTopupIfBelowThreshold(cycles_requester);
  };

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

  public query func get_installation_id() : async Int {
    installation_id;
  };

  public query func get_version() : async Nat {
    101;
  };
};
