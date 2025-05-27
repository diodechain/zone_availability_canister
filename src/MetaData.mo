
type VETKD_SYSTEM_API = actor {
    vetkd_public_key : ({
        canister_id : ?Principal;
        context : Blob;
        key_id : { curve : { #bls12_381_g2 }; name : Text };
    }) -> async ({ public_key : Blob });
    vetkd_derive_encrypted_key : ({
        input : Blob;
        context : Blob;
        transport_public_key : Blob;
        key_id : { curve : { #bls12_381_g2 }; name : Text };
    }) -> async ({ encrypted_key : Blob });
};

let vetkd_system_api : VETKD_SYSTEM_API = actor ("s55qq-oqaaa-aaaaa-aaakq-cai");

module {

}