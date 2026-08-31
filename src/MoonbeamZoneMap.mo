import Text "mo:base/Text";

// Embedded Moonbeam → Base address map for one-shot upgrade migration.
// Keep in sync with ddrive Model.MoonbeamZoneMap (version 1787642000).
// Keys/values are lowercase 0x-prefixed 20-byte addresses.
module MoonbeamZoneMap {
  public let version : Text = "1787642000";

  let pairs : [(Text, Text)] = [
    ("0x05eee5fcecb9074579a575700ae3499a7d109fde", "0x2bac42e55aa93f232ce7752dbafa647860bcbb0b"),
    ("0x0abc455e08177a7541039c0f0eed836ecf7c5bee", "0x3cf7f7738db8edff4bd2267029b20b5bf2083eba"),
    ("0x2dec1efe3bc0077447df1354356ae5839c3684b7", "0xb65b3baf26f185ed43ef3a179c9a1a0b66968ae4"),
    ("0x6aee3f62f9c30c62392b85c2eb47190ce2e11e06", "0xeaa6ba0c0cdb196133f0024d8dfa9ee7aaa7105a"),
    ("0x88ac6a130178daabff3806bc55922d911c736f04", "0x191db414eed65712d782b89ba678429d78170aae"),
  ];

  public func normalize(addr : Text) : Text {
    Text.toLowercase(addr);
  };

  public func zone_base(moonbeam_zone_id : Text) : ?Text {
    let key = normalize(moonbeam_zone_id);
    for ((moon, base) in pairs.vals()) {
      if (moon == key) {
        return ?base;
      };
    };
    null;
  };
};
