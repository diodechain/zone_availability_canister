import Array "mo:base/Array";
import Base16 "mo:base16/Base16";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Sha256 "mo:sha2/Sha256";
import SHA3 "mo:sha3";
import Types "./Types";

module {
  let ic : Types.IC = actor ("aaaaa-aa");

  public func addressFromPrincipal(who : Principal) : async ?Blob {
    let caller = Principal.toBlob(who);

    try {
      Debug.print("Getting public key");
      let { public_key } = await ic.ecdsa_public_key({
        canister_id = null;
        derivation_path = [caller];
        key_id = { curve = #secp256k1; name = "dfx_test_key" };
      });

      Debug.print("Converting public key to address");
      let ret = addressFromPublicKey(public_key);
      Debug.print("Got address: " # Base16.encode(ret));
      ?ret;
    } catch (e) {
      Debug.print("Error getting public key");
      Debug.print(Error.message(e));
      null;
    };
  };

  func derFromPublicKey(public_key : Blob) : Blob {
    let prefix : [Nat8] = [48, 86, 48, 16, 6, 7, 42, 134, 72, 206, 61, 2, 1, 6, 5, 43, 129, 4, 0, 10, 3, 66, 0];
    Blob.fromArray(Array.append(prefix, Blob.toArray(public_key)));
  };

  public func addressFromPublicKey(public_key : Blob) : Blob {
    var pubkey = Blob.toArray(public_key);
    if (Array.size(pubkey) != 65) {
      Debug.trap("Invalid public key size: " # debug_show (Array.size(pubkey)));
    };
    Debug.print("Pubkey: " # Base16.encode(Blob.fromArray(pubkey)));
    let subject = Array.subArray(pubkey, 1, 64);
    var sha = SHA3.Keccak(256);
    sha.update(subject);
    let result = sha.finalize();
    Blob.fromArray(Array.subArray(result, 12, 20));
  };

  public func principalFromPublicKey(public_key : Blob) : Principal {
    var pubkey = Blob.toArray(public_key);
    if (Array.size(pubkey) != 65) {
      Debug.trap("Invalid public key size: " # debug_show (Array.size(pubkey)));
    };
    Debug.print("Pubkey: " # Base16.encode(Blob.fromArray(pubkey)));
    let hash = Blob.toArray(Sha256.fromBlob(#sha224, derFromPublicKey(public_key)));
    let id = Blob.fromArray(Array.append<Nat8>(hash, [2]));
    Principal.fromBlob(id);
  };
};
