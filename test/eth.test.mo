import { test; suite } "mo:test";
import Eth "../src/Eth";
import Debug "mo:base/Debug";
import Base16 "mo:base16/Base16";

test(
  "Convert public key to eth address",
  func() {
    let pubkey = "0406777bd9e804bc47039449737c98e8aceaf7d48f5df7b85c41e09628de8f17fbe09e0e5d8c0d8eee079c4019078a92158c8bb027ad5c8954b30ddc113cea71d5";
    let pubkey_bytes = Base16.decode(pubkey);
    switch (pubkey_bytes) {
      case (null) {
        assert false;
      };
      case (?pubkey_bytes) {
        let address_bytes = Eth.addressFromPublicKey(pubkey_bytes);
        let address = Base16.encode(address_bytes);
        Debug.print(debug_show (address));
        assert address == "fd86d5ea6d811556da1470de4fcfe0a52fe8832e";
      };
    };
  },
);
