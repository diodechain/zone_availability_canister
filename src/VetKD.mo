// https://github.com/dfinity/examples/blob/37a7954536b41ea5839830be97bafb2c06e27384/motoko/encrypted-notes-dapp-vetkd/src/encrypted_notes_motoko/main.mo#L314
type SYSTEM_API = actor {
  vetkd_public_key : ({
    canister_id : ?Principal;
    context : Blob;
    key_id : { curve : { #bls12_381_g2 }; name : Text };
  }) -> async ({ public_key : Blob });
  vetkd_derive_key : ({
    input : Blob;
    context : Blob;
    transport_public_key : Blob;
    key_id : { curve : { #bls12_381_g2 }; name : Text };
  }) -> async ({ encrypted_key : Blob });
};

let system_api : SYSTEM_API = actor ("aaaaa-aa");
