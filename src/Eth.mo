import Types "./Types";
import Principal "mo:base/Principal";
import SHA3 "mo:sha3";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Error "mo:base/Error";

module {
  let ic : Types.IC = actor("aaaaa-aa");

  public func addressFromPrincipal(who : Principal) : async ?Blob {
    let caller = Principal.toBlob(who);

    try {
      let { public_key } = await ic.ecdsa_public_key({
          canister_id = null;
          derivation_path = [ caller ];
          key_id = { curve = #secp256k1; name = "test_key_1" };
      });

      ?addressFromPublicKey(public_key)
    } catch (e) {
      Debug.print(Error.message(e));
      null
    }
  };

  public func addressFromPublicKey(public_key : Blob) : Blob {
    let pubkey = Blob.toArray(public_key);
    let subject = Array.subArray(pubkey, 1, 64);
    var sha = SHA3.Keccak(256);
    sha.update(subject);
    let result = sha.finalize();
    Blob.fromArray(Array.subArray(result, 12, 20))
  };
};
