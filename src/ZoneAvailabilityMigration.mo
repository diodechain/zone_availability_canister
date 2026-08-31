import Blob "mo:base/Blob";
import EthRpc "./EthRpc";
import Map "mo:map/Map";
import MemberCache "./MemberCache";
import MoonbeamZoneMap "./MoonbeamZoneMap";
import Oracle "./Oracle";

module ZoneAvailabilityMigration {
  // Pre-v415 cache shape (rpc_host / rpc_path, with call_token).
  public type CacheV414 = {
    zone_id : Text;
    rpc_host : Text;
    rpc_path : Text;
    zone_members : Map.Map<Blob, MemberCache.CacheEntry>;
    transform_function : Oracle.TransformFunction;
    call_token : ?Blob;
  };

  public func migrate_cache(old : CacheV414) : MemberCache.Cache {
    switch (MoonbeamZoneMap.zone_base(old.zone_id)) {
      case (?base_zone_id) {
        {
          zone_id = base_zone_id;
          backend = #ChainFusion({ network = #BaseMainnet });
          zone_members = Map.new();
          transform_function = old.transform_function;
          call_token = old.call_token;
        };
      };
      case null {
        let backend = EthRpc.backend_from_legacy_host(old.rpc_host, old.rpc_path);
        {
          zone_id = old.zone_id;
          backend = backend;
          zone_members = old.zone_members;
          transform_function = old.transform_function;
          call_token = old.call_token;
        };
      };
    };
  };

  public func migration(old : {
    var zone_members : CacheV414;
  }) : {
    var zone_members : MemberCache.Cache;
  } {
    {
      var zone_members = migrate_cache(old.zone_members);
    };
  };
};
