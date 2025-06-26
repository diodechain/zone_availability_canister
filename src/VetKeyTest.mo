import Blob "mo:base/Blob";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import VetKD "VetKD";
actor VetKeyTest {
  public shared func vetkd_public_key(
    canister_id : ?Principal,
    context : Blob,
    key_id : { curve : { #bls12_381_g2 }; name : Text },
  ) : async Blob {
    (await VetKD.system_api.vetkd_public_key({ canister_id = canister_id; context = context; key_id = key_id })).public_key;
  };

  public shared func vetkd_derive_key(
    input : Blob,
    context : Blob,
    transport_public_key : Blob,
    key_id : { curve : { #bls12_381_g2 }; name : Text },
  ) : async Blob {
    let response = await (with cycles = 26_153_846_153) VetKD.system_api.vetkd_derive_key({
      input = input;
      context = context;
      transport_public_key = transport_public_key;
      key_id = key_id;
    });
    response.encrypted_key;
  };
};
