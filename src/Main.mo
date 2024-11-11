import Result "mo:base/Result";
import Nat32 "mo:base/Nat32";
import Sha256 "mo:sha2/Sha256";
import DiodeMessages "./DiodeMessages";
import Oracle "./Oracle";

shared (_init_msg) actor class Main(
  _args : {
    zone_id : Text;
    rpc_host : Text;
    rpc_path : Text;
  }
) = this {
  stable var zone_id = _args.zone_id;
  stable var rpc_host = _args.rpc_host;
  stable var rpc_path = _args.rpc_path;
  stable var dm : DiodeMessages.MessageStore = DiodeMessages.new();

  public shared func add_message(key_id : Blob, ciphertext : Blob) : async Result.Result<(), Text> {
    let hash = Sha256.fromBlob(#sha256, ciphertext);
    DiodeMessages.add_message(dm, key_id, hash, ciphertext);
  };

  public shared func add_messages(messages : [(Blob, Blob)]) : async Result.Result<(), Text> {
    for ((key_id, ciphertext) in messages.vals()) {
      let hash = Sha256.fromBlob(#sha256, ciphertext);
      switch (DiodeMessages.add_message(dm, key_id, hash, ciphertext)) {
        case (#err(e)) {
          return #err(e);
        };
        case (#ok) {};
      };
    };
    #ok;
  };

  public shared query func get_message_by_hash(message_hash : Blob) : async ?DiodeMessages.Message {
    DiodeMessages.get_message_by_hash(dm, message_hash);
  };

  public shared query func get_message_by_id(message_id : Nat32) : async DiodeMessages.Message {
    DiodeMessages.get_message_by_id(dm, message_id);
  };

  public shared query func get_messages_by_range(min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
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

  public shared query func get_messages_by_range_for_key(key_id : Blob, min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
    DiodeMessages.get_messages_by_range_for_key(dm, key_id, min_message_id, max_message_id);
  };

  public shared func get_zone_members() : async ?Blob {
    await Oracle.get_zone_members(zone_id, rpc_host, rpc_path);
  };

  public shared func get_zone_member_role(member_address : Text) : async Nat {
    await Oracle.get_zone_member_role(zone_id, member_address, rpc_host, rpc_path);
  };

  public shared func test_record_output() : async ((Nat32, Nat32)) {
    (0, 1);
  };

  public shared func test_record_input(record : (Nat32, Nat32)) : async Nat32 {
    let (a, b) = record;
    a + b;
  };

};
