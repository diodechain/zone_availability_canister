module {
  public type BitcoinAddress = Text;
  public type BitcoinBlockHash = Blob;
  public type BitcoinBlockHeader = Blob;
  public type BitcoinBlockHeight = Nat32;
  public type BitcoinGetBalanceArgs = {
    network : BitcoinNetwork;
    address : BitcoinAddress;
    min_confirmations : ?Nat32;
  };
  public type BitcoinGetBalanceResult = Satoshi;
  public type BitcoinGetBlockHeadersArgs = {
    start_height : BitcoinBlockHeight;
    end_height : ?BitcoinBlockHeight;
    network : BitcoinNetwork;
  };
  public type BitcoinGetBlockHeadersResult = {
    tip_height : BitcoinBlockHeight;
    block_headers : [BitcoinBlockHeader];
  };
  public type BitcoinGetCurrentFeePercentilesArgs = {
    network : BitcoinNetwork;
  };
  public type BitcoinGetCurrentFeePercentilesResult = [
    MillisatoshiPerByte
  ];
  public type BitcoinGetUtxosArgs = {
    network : BitcoinNetwork;
    filter : ?{ #page : Blob; #min_confirmations : Nat32 };
    address : BitcoinAddress;
  };
  public type BitcoinGetUtxosResult = {
    next_page : ?Blob;
    tip_height : BitcoinBlockHeight;
    tip_block_hash : BitcoinBlockHash;
    utxos : [Utxo];
  };
  public type BitcoinNetwork = { #mainnet; #testnet; #regtest };
  public type BitcoinSendTransactionArgs = {
    transaction : Blob;
    network : BitcoinNetwork;
  };
  public type CanisterId = Principal;
  public type CanisterInfoArgs = {
    canister_id : CanisterId;
    num_requested_changes : ?Nat64;
  };
  public type CanisterInfoResult = {
    controllers : [Principal];
    module_hash : ?Blob;
    recent_changes : [Change];
    total_num_changes : Nat64;
  };
  public type CanisterInstallMode = {
    #reinstall;
    #upgrade : ?{
      wasm_memory_persistence : ?{ #keep; #replace };
      skip_pre_upgrade : ?Bool;
    };
    #install;
  };
  public type CanisterLogRecord = {
    idx : Nat64;
    timestamp_nanos : Nat64;
    content : Blob;
  };
  public type CanisterSettings = {
    freezing_threshold : ?Nat;
    controllers : ?[Principal];
    reserved_cycles_limit : ?Nat;
    log_visibility : ?LogVisibility;
    wasm_memory_limit : ?Nat;
    memory_allocation : ?Nat;
    compute_allocation : ?Nat;
  };
  public type CanisterStatusArgs = { canister_id : CanisterId };
  public type CanisterStatusResult = {
    status : { #stopped; #stopping; #running };
    memory_size : Nat;
    cycles : Nat;
    settings : DefiniteCanisterSettings;
    query_stats : {
      response_payload_bytes_total : Nat;
      num_instructions_total : Nat;
      num_calls_total : Nat;
      request_payload_bytes_total : Nat;
    };
    idle_cycles_burned_per_day : Nat;
    module_hash : ?Blob;
    reserved_cycles : Nat;
  };
  public type Change = {
    timestamp_nanos : Nat64;
    canister_version : Nat64;
    origin : ChangeOrigin;
    details : ChangeDetails;
  };
  public type ChangeDetails = {
    #creation : { controllers : [Principal] };
    #code_deployment : {
      mode : { #reinstall; #upgrade; #install };
      module_hash : Blob;
    };
    #load_snapshot : {
      canister_version : Nat64;
      taken_at_timestamp : Nat64;
      snapshot_id : SnapshotId;
    };
    #controllers_change : { controllers : [Principal] };
    #code_uninstall;
  };
  public type ChangeOrigin = {
    #from_user : { user_id : Principal };
    #from_canister : { canister_version : ?Nat64; canister_id : Principal };
  };
  public type ChunkHash = { hash : Blob };
  public type ClearChunkStoreArgs = { canister_id : CanisterId };
  public type CreateCanisterArgs = {
    settings : ?CanisterSettings;
    sender_canister_version : ?Nat64;
  };
  public type CreateCanisterResult = { canister_id : CanisterId };
  public type DefiniteCanisterSettings = {
    freezing_threshold : Nat;
    controllers : [Principal];
    reserved_cycles_limit : Nat;
    log_visibility : LogVisibility;
    wasm_memory_limit : Nat;
    memory_allocation : Nat;
    compute_allocation : Nat;
  };
  public type DeleteCanisterArgs = { canister_id : CanisterId };
  public type DeleteCanisterSnapshotArgs = {
    canister_id : CanisterId;
    snapshot_id : SnapshotId;
  };
  public type DepositCyclesArgs = { canister_id : CanisterId };
  public type EcdsaCurve = { #secp256k1 };
  public type EcdsaPublicKeyArgs = {
    key_id : { name : Text; curve : EcdsaCurve };
    canister_id : ?CanisterId;
    derivation_path : [Blob];
  };
  public type EcdsaPublicKeyResult = {
    public_key : Blob;
    chain_code : Blob;
  };
  public type FetchCanisterLogsArgs = { canister_id : CanisterId };
  public type FetchCanisterLogsResult = {
    canister_log_records : [CanisterLogRecord];
  };
  public type HttpHeader = { value : Text; name : Text };
  public type HttpRequestArgs = {
    url : Text;
    method : { #get; #head; #post };
    max_response_bytes : ?Nat64;
    body : ?Blob;
    transform : ?{
      function : shared query {
        context : Blob;
        response : HttpRequestResult;
      } -> async HttpRequestResult;
      context : Blob;
    };
    headers : [HttpHeader];
  };
  public type HttpRequestResult = {
    status : Nat;
    body : Blob;
    headers : [HttpHeader];
  };
  public type InstallChunkedCodeArgs = {
    arg : Blob;
    wasm_module_hash : Blob;
    mode : CanisterInstallMode;
    chunk_hashes_list : [ChunkHash];
    target_canister : CanisterId;
    store_canister : ?CanisterId;
    sender_canister_version : ?Nat64;
  };
  public type InstallCodeArgs = {
    arg : Blob;
    wasm_module : WasmModule;
    mode : CanisterInstallMode;
    canister_id : CanisterId;
    sender_canister_version : ?Nat64;
  };
  public type ListCanisterSnapshotsArgs = { canister_id : CanisterId };
  public type ListCanisterSnapshotsResult = [Snapshot];
  public type LoadCanisterSnapshotArgs = {
    canister_id : CanisterId;
    sender_canister_version : ?Nat64;
    snapshot_id : SnapshotId;
  };
  public type LogVisibility = { #controllers; #public_ };
  public type MillisatoshiPerByte = Nat64;
  public type NodeMetrics = {
    num_block_failures_total : Nat64;
    node_id : Principal;
    num_blocks_proposed_total : Nat64;
  };
  public type NodeMetricsHistoryArgs = {
    start_at_timestamp_nanos : Nat64;
    subnet_id : Principal;
  };
  public type NodeMetricsHistoryResult = [{
    timestamp_nanos : Nat64;
    node_metrics : [NodeMetrics];
  }];
  public type Outpoint = { txid : Blob; vout : Nat32 };
  public type ProvisionalCreateCanisterWithCyclesArgs = {
    settings : ?CanisterSettings;
    specified_id : ?CanisterId;
    amount : ?Nat;
    sender_canister_version : ?Nat64;
  };
  public type ProvisionalCreateCanisterWithCyclesResult = {
    canister_id : CanisterId;
  };
  public type ProvisionalTopUpCanisterArgs = {
    canister_id : CanisterId;
    amount : Nat;
  };
  public type RawRandResult = Blob;
  public type Satoshi = Nat64;
  public type SchnorrAlgorithm = { #ed25519; #bip340secp256k1 };
  public type SchnorrPublicKeyArgs = {
    key_id : { algorithm : SchnorrAlgorithm; name : Text };
    canister_id : ?CanisterId;
    derivation_path : [Blob];
  };
  public type SchnorrPublicKeyResult = {
    public_key : Blob;
    chain_code : Blob;
  };
  public type SignWithEcdsaArgs = {
    key_id : { name : Text; curve : EcdsaCurve };
    derivation_path : [Blob];
    message_hash : Blob;
  };
  public type SignWithEcdsaResult = { signature : Blob };
  public type SignWithSchnorrArgs = {
    key_id : { algorithm : SchnorrAlgorithm; name : Text };
    derivation_path : [Blob];
    message : Blob;
  };
  public type SignWithSchnorrResult = { signature : Blob };
  public type Snapshot = {
    id : SnapshotId;
    total_size : Nat64;
    taken_at_timestamp : Nat64;
  };
  public type SnapshotId = Blob;
  public type StartCanisterArgs = { canister_id : CanisterId };
  public type StopCanisterArgs = { canister_id : CanisterId };
  public type StoredChunksArgs = { canister_id : CanisterId };
  public type StoredChunksResult = [ChunkHash];
  public type TakeCanisterSnapshotArgs = {
    replace_snapshot : ?SnapshotId;
    canister_id : CanisterId;
  };
  public type TakeCanisterSnapshotResult = Snapshot;
  public type uninstall_code_args = {
    canister_id : CanisterId;
    sender_canister_version : ?Nat64;
  };
  public type UpdateSettingsArgs = {
    canister_id : Principal;
    settings : CanisterSettings;
    sender_canister_version : ?Nat64;
  };
  public type UploadChunkArgs = { chunk : Blob; canister_id : Principal };
  public type UploadChunkResult = ChunkHash;
  public type Utxo = { height : Nat32; value : Satoshi; outpoint : Outpoint };
  public type WasmModule = Blob;

  public type Service = actor {
    bitcoin_get_balance : shared BitcoinGetBalanceArgs -> async BitcoinGetBalanceResult;
    bitcoin_get_block_headers : shared BitcoinGetBlockHeadersArgs -> async BitcoinGetBlockHeadersResult;
    bitcoin_get_current_fee_percentiles : shared BitcoinGetCurrentFeePercentilesArgs -> async BitcoinGetCurrentFeePercentilesResult;
    bitcoin_get_utxos : shared BitcoinGetUtxosArgs -> async BitcoinGetUtxosResult;
    bitcoin_send_transaction : shared BitcoinSendTransactionArgs -> async ();
    canister_info : shared CanisterInfoArgs -> async CanisterInfoResult;
    canister_status : shared CanisterStatusArgs -> async CanisterStatusResult;
    clear_chunk_store : shared ClearChunkStoreArgs -> async ();
    create_canister : shared CreateCanisterArgs -> async CreateCanisterResult;
    delete_canister : shared DeleteCanisterArgs -> async ();
    delete_canister_snapshot : shared DeleteCanisterSnapshotArgs -> async ();
    deposit_cycles : shared DepositCyclesArgs -> async ();
    ecdsa_public_key : shared EcdsaPublicKeyArgs -> async EcdsaPublicKeyResult;
    fetch_canister_logs : shared query FetchCanisterLogsArgs -> async FetchCanisterLogsResult;
    http_request : shared HttpRequestArgs -> async HttpRequestResult;
    install_chunked_code : shared InstallChunkedCodeArgs -> async ();
    install_code : shared InstallCodeArgs -> async ();
    list_canister_snapshots : shared ListCanisterSnapshotsArgs -> async ListCanisterSnapshotsResult;
    load_canister_snapshot : shared LoadCanisterSnapshotArgs -> async ();
    node_metrics_history : shared NodeMetricsHistoryArgs -> async NodeMetricsHistoryResult;
    provisional_create_canister_with_cycles : shared ProvisionalCreateCanisterWithCyclesArgs -> async ProvisionalCreateCanisterWithCyclesResult;
    provisional_top_up_canister : shared ProvisionalTopUpCanisterArgs -> async ();
    raw_rand : shared () -> async RawRandResult;
    schnorr_public_key : shared SchnorrPublicKeyArgs -> async SchnorrPublicKeyResult;
    sign_with_ecdsa : shared SignWithEcdsaArgs -> async SignWithEcdsaResult;
    sign_with_schnorr : shared SignWithSchnorrArgs -> async SignWithSchnorrResult;
    start_canister : shared StartCanisterArgs -> async ();
    stop_canister : shared StopCanisterArgs -> async ();
    stored_chunks : shared StoredChunksArgs -> async StoredChunksResult;
    take_canister_snapshot : shared TakeCanisterSnapshotArgs -> async TakeCanisterSnapshotResult;
    uninstall_code : shared uninstall_code_args -> async ();
    update_settings : shared UpdateSettingsArgs -> async ();
    upload_chunk : shared UploadChunkArgs -> async UploadChunkResult;

    stable_size : shared () -> async Nat32;
    stable64_size : shared () -> async Nat64;
  };

  public let ic = actor ("aaaaa-aa") : Service;
};
