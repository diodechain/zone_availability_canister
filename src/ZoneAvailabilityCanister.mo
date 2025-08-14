import Array "mo:base/Array";
import Cycles "mo:base/ExperimentalCycles";
import CyclesManager "mo:cycles-manager/CyclesManager";
import CyclesRequester "mo:cycles-manager/CyclesRequester";
import Debug "mo:base/Debug";
import DiodeMessages "./DiodeMessages";
import DiodeFileSystem "./DiodeFileSystem";
import MemberCache "./MemberCache";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Oracle "./Oracle";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Sha256 "mo:sha2/Sha256";
import Types "./Types";
import Time "mo:base/Time";
import MetaData "./MetaData";
import Prim "mo:⛔";
import DiodeAttachments "./DiodeAttachments";

shared (_init_msg) persistent actor class ZoneAvailabilityCanister(
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

  var dm : DiodeMessages.MessageStore = DiodeMessages.new();
  var zone_members : MemberCache.Cache = MemberCache.new(_args.zone_id, _args.rpc_host, _args.rpc_path, oracle_transform_function);
  var installation_id : Int = Time.now();
  var meta_data : MetaData.MetaData = MetaData.new();
  var attachments : DiodeAttachments.AttachmentStore = DiodeAttachments.new(128_000_000);
  var file_system : DiodeFileSystem.FileSystem = DiodeFileSystem.new(128_000_000);

  // Topup rule based on https://cycleops.notion.site/Best-Practices-for-Top-up-Rules-e3e9458ec96f46129533f58016f66f6e
  // When below .7 trillion cycles, topup by .5 trillion (~65 cents)
  var cycles_requester : CyclesRequester.CyclesRequester = CyclesRequester.init({
    batteryCanisterPrincipal = _args.cycles_requester_id;
    topupRule = {
      threshold = 700_000_000_000;
      method = #by_amount(500_000_000_000);
    };
  });

  /**
   * DiodeMessages API
   */

  public shared (msg) func add_message(key_id : Blob, ciphertext : Blob) : async Result.Result<Nat32, Text> {
    ignore await request_topup_if_low();
    assert_membership(msg.caller);

    let hash = Sha256.fromBlob(#sha256, ciphertext);
    DiodeMessages.add_message(dm, key_id, hash, ciphertext);
  };

  public shared (msg) func add_messages(messages : [(Blob, Blob)]) : async Result.Result<[Nat32], Text> {
    ignore await request_topup_if_low();
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

  public query (msg) func get_message_by_hash(message_hash : Blob) : async ?DiodeMessages.Message {
    assert_membership(msg.caller);
    DiodeMessages.get_message_by_hash(dm, message_hash);
  };

  public query (msg) func get_message_by_id(message_id : Nat32) : async DiodeMessages.Message {
    assert_membership(msg.caller);
    DiodeMessages.get_message_by_id(dm, message_id);
  };

  public query (msg) func get_messages_by_range(min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
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

  public query (msg) func get_messages_by_range_for_key(key_id : Blob, min_message_id : Nat32, max_message_id : Nat32) : async [DiodeMessages.Message] {
    assert_membership(msg.caller);
    DiodeMessages.get_messages_by_range_for_key(dm, key_id, min_message_id, max_message_id);
  };

  /**
   * MemberCache API
   */

  public query (msg) func my_role() : async Nat {
    MemberCache.get_role(zone_members, msg.caller);
  };

  public shared query func get_role(member : Principal) : async Nat {
    MemberCache.get_role(zone_members, member);
  };

  public func update_role(public_key : Blob) : async Nat {
    ignore await request_topup_if_low();
    await MemberCache.update_member(zone_members, public_key);
  };

  public func update_identity_role(public_key : Blob, identity_contract_address : Blob) : async Nat {
    ignore await request_topup_if_low();
    await MemberCache.update_identity_member(zone_members, public_key, identity_contract_address);
  };

  public query func get_message_usage() : async Nat64 {
    DiodeMessages.get_usage(dm);
  };

  public query func get_message_count() : async Nat {
    DiodeMessages.get_count(dm);
  };

  /**
   * MetaData API
   */

  public shared (msg) func set_public_and_protected_key(public_key : Blob, vet_protected_key : Blob) {
    assert_admin(msg.caller);
    ignore await request_topup_if_low();
    MetaData.set_public_and_protected_key(meta_data, public_key, vet_protected_key);
  };

  public query func get_meta_data_info() : async MetaData.MetaDataInfo {
    MetaData.get_meta_data_info(meta_data);
  };

  public query (msg) func get_data_entry(key : Nat8) : async ?MetaData.DataEntry {
    assert_membership(msg.caller);
    MetaData.get_data_entry(meta_data, key);
  };

  public shared (msg) func set_data_entry(key : Nat8, data : Blob) {
    assert_admin(msg.caller);
    ignore await request_topup_if_low();
    MetaData.set_data_entry(meta_data, key, data);
  };

  public shared (msg) func delete_data_entry(key : Nat8) {
    assert_admin(msg.caller);
    ignore await request_topup_if_low();
    MetaData.delete_data_entry(meta_data, key);
  };

  public query (msg) func get_timestamps() : async [MetaData.DirectoryEntry] {
    assert_membership(msg.caller);
    MetaData.get_timestamps(meta_data);
  };

  public shared (msg) func derive_vet_protector_key(transport_public_key : Blob, target_public_key : Blob) : async ?Blob {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    await MetaData.derive_vet_protector_key(meta_data, transport_public_key, target_public_key);
  };

  /**
   * DiodeAttachments API
   */

  public shared (msg) func write_attachment(identity_hash : Blob, data : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeAttachments.write_attachment(attachments, identity_hash, data);
  };

  public shared (msg) func delete_attachment(identity_hash : Blob) {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeAttachments.delete_attachment(attachments, identity_hash);
  };

  public query (msg) func get_attachment(identity_hash : Blob) : async Result.Result<Blob, Text> {
    assert_membership(msg.caller);
    switch (DiodeAttachments.get_attachment(attachments, identity_hash)) {
      case (#err(e)) {
        #err(e);
      };
      case (#ok(attachment)) {
        #ok(attachment.ciphertext);
      };
    };
  };

  public query (msg) func get_attachment_metadata(identity_hash : Blob) : async Result.Result<DiodeAttachments.AttachmentMetadata, Text> {
    assert_membership(msg.caller);
    DiodeAttachments.get_attachment_metadata(attachments, identity_hash);
  };

  public shared (msg) func allocate_attachment(identity_hash : Blob, size : Nat64) : async Result.Result<Nat64, Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeAttachments.allocate_attachment(attachments, identity_hash, size);
  };

  public shared (msg) func write_attachment_chunk(identity_hash : Blob, offset : Nat64, data : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeAttachments.write_attachment_chunk(attachments, identity_hash, offset, data);
  };

  public shared (msg) func finalize_attachment(identity_hash : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeAttachments.finalize_attachment(attachments, identity_hash);
  };

  public query (msg) func read_attachment_chunk(identity_hash : Blob, offset : Nat64, size : Nat) : async Result.Result<Blob, Text> {
    assert_membership(msg.caller);
    DiodeAttachments.read_attachment_chunk(attachments, identity_hash, offset, size);
  };

  public query func get_attachment_usage() : async Nat64 {
    DiodeAttachments.get_usage(attachments);
  };

  public query func get_attachment_max_usage() : async Nat64 {
    DiodeAttachments.get_max_usage(attachments);
  };

  public query func get_attachment_count() : async Nat {
    DiodeAttachments.get_count(attachments);
  };

  /**
   * DiodeFileSystem API
   */

  public shared (msg) func create_directory(directory_id : Blob, name_hash : Blob, parent_id : ?Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.create_directory(file_system, directory_id, name_hash, parent_id);
  };

  public shared (msg) func add_file(directory_id : Blob, name_hash : Blob, content_hash : Blob, ciphertext : Blob) : async Result.Result<Nat, Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.add_file(file_system, directory_id, name_hash, content_hash, ciphertext);
  };

  public shared (msg) func write_file(directory_id : Blob, name_hash : Blob, content_hash : Blob, ciphertext : Blob) : async Result.Result<Nat, Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.write_file(file_system, directory_id, name_hash, content_hash, ciphertext);
  };

  public shared (msg) func delete_file(content_hash : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.delete_file(file_system, content_hash);
  };

  public shared (msg) func allocate_file(directory_id : Blob, name_hash : Blob, content_hash : Blob, size : Nat64) : async Result.Result<Nat, Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.allocate_file(file_system, directory_id, name_hash, content_hash, size);
  };

  public shared (msg) func write_file_chunk(content_hash : Blob, chunk_offset : Nat64, chunk : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.write_file_chunk(file_system, content_hash, chunk_offset, chunk);
  };

  public shared (msg) func finalize_file(content_hash : Blob) : async Result.Result<(), Text> {
    assert_membership(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.finalize_file(file_system, content_hash);
  };

  public query (msg) func read_file_chunk(content_hash : Blob, chunk_offset : Nat64, chunk_size : Nat) : async Result.Result<Blob, Text> {
    assert_membership(msg.caller);
    DiodeFileSystem.read_file_chunk(file_system, content_hash, chunk_offset, chunk_size);
  };

  public query (msg) func get_file_by_hash(content_hash : Blob) : async Result.Result<DiodeFileSystem.File, Text> {
    assert_membership(msg.caller);
    DiodeFileSystem.get_file_by_hash(file_system, content_hash);
  };

  public query (msg) func get_file_by_id(file_id : Nat) : async ?DiodeFileSystem.File {
    assert_membership(msg.caller);
    DiodeFileSystem.get_file_by_id(file_system, file_id);
  };

  public query (msg) func get_directory(directory_id : Blob) : async ?DiodeFileSystem.Directory {
    assert_membership(msg.caller);
    DiodeFileSystem.get_directory(file_system, directory_id);
  };

  public query (msg) func get_files_in_directory(directory_id : Blob) : async [DiodeFileSystem.File] {
    assert_membership(msg.caller);
    DiodeFileSystem.get_files_in_directory(file_system, directory_id);
  };

  public query (msg) func get_child_directories(directory_id : Blob) : async [DiodeFileSystem.Directory] {
    assert_membership(msg.caller);
    DiodeFileSystem.get_child_directories(file_system, directory_id);
  };

  public query func get_file_system_usage() : async Nat64 {
    DiodeFileSystem.get_usage(file_system);
  };

  public query func get_file_system_max_usage() : async Nat64 {
    DiodeFileSystem.get_max_usage(file_system);
  };

  public query func get_file_count() : async Nat {
    DiodeFileSystem.get_file_count(file_system);
  };

  public query func get_directory_count() : async Nat {
    DiodeFileSystem.get_directory_count(file_system);
  };

  public shared (msg) func set_file_system_max_storage(max_storage : Nat64) {
    assert_admin(msg.caller);
    ignore await request_topup_if_low();
    DiodeFileSystem.set_max_storage(file_system, max_storage);
  };

  public query func get_last_file_id() : async Nat {
    DiodeFileSystem.get_last_file_id(file_system);
  };

  /**
   * Public System API
   */

  // From https://github.com/CycleOperators/cycles-manager/blob/main/example/Child.mo
  public shared func request_topup_if_low() : async CyclesManager.TransferCyclesResult {
    await* CyclesRequester.requestTopupIfBelowThreshold(cycles_requester);
  };

  public query func get_zone_id() : async Text {
    zone_members.zone_id;
  };

  public query func get_cycles_balance() : async Nat {
    Cycles.balance();
  };

  public query func get_installation_id() : async Int {
    installation_id;
  };

  public query func get_version() : async Nat {
    407;
  };

  public query func get_stable_storage_size() : async Nat {
    Prim.rts_stable_memory_size();
  };

  public query func get_logical_stable_storage_size() : async Nat {
    Prim.rts_logical_stable_memory_size();
  };

  /**
   * Private functions
   */

  private func assert_membership(member : Principal) {
    let role = MemberCache.get_role(zone_members, member);
    if (role == 0) {
      Debug.trap("Not a member of the zone");
    };
  };

  private func assert_admin(member : Principal) {
    let role = MemberCache.get_role(zone_members, member);
    if (role < 400) {
      Debug.trap("Not an admin");
    };
  };
};
