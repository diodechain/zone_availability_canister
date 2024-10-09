import Result "mo:base/Result";
import Nat32 "mo:base/Nat32";
import DiodeMessages "./DiodeMessages";

actor {
  stable var dm: DiodeMessages.MessageStore = DiodeMessages.new();

  public func add_message(key_id: Blob, hash: Blob, ciphertext: Blob) : async Result.Result<(), Text> {
    DiodeMessages.add_message(dm, key_id, hash, ciphertext);
  };

  public shared query func get_message_by_hash(message_hash: Blob) : async ?DiodeMessages.Message {
    DiodeMessages.get_message_by_hash(dm, message_hash);
  };

  public shared query func get_message_by_id(message_id: Nat32) : async DiodeMessages.Message {
    DiodeMessages.get_message_by_id(dm, message_id);
  };

  public shared query func get_min_message_id() : async Nat32 {
    DiodeMessages.get_min_message_id(dm);
  };

  public shared query func get_max_message_id() : async Nat32 {
    DiodeMessages.get_max_message_id(dm);
  };

  public shared query func get_min_message_id_by_key(key_id: Blob) : async ?Nat32 {
    DiodeMessages.get_min_message_id_by_key(dm, key_id);
  };

  public shared query func get_max_message_id_by_key(key_id: Blob) : async ?Nat32 {
    DiodeMessages.get_max_message_id_by_key(dm, key_id);
  };
};
