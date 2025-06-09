import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";

actor VetKeyTest {
    // https://github.com/dfinity/examples/blob/37a7954536b41ea5839830be97bafb2c06e27384/motoko/encrypted-notes-dapp-vetkd/src/encrypted_notes_motoko/main.mo#L314
    type VETKD_SYSTEM_API = actor {
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

    let vetkd_system_api : VETKD_SYSTEM_API = actor ("aaaaa-aa");

    public shared func vetkd_public_key(
        canister_id : ?Principal,
        context : Blob,
        key_id : { curve : { #bls12_381_g2 }; name : Text }
    ) : async Blob {
        (await vetkd_system_api.vetkd_public_key({
            canister_id = canister_id;
            context = context;
            key_id = key_id;
        })).public_key;
    };

    public shared func vetkd_derive_key(
        input : Blob,
        context : Blob,
        transport_public_key : Blob,
        key_id : { curve : { #bls12_381_g2 }; name : Text }
    ) : async Blob {
        Cycles.add<system>(30_000_000_000);
        let response = await vetkd_system_api.vetkd_derive_key({
            input = input;
            context = context;
            transport_public_key = transport_public_key;
            key_id = key_id;
        });
        response.encrypted_key;
    };
}
