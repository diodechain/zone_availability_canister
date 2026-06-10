import Map "mo:map/Map";
import MemberCache "./MemberCache";
import Oracle "./Oracle";

module ZoneAvailabilityMigration {
  public type CacheV412 = {
    zone_id : Text;
    rpc_host : Text;
    rpc_path : Text;
    zone_members : Map.Map<Blob, MemberCache.CacheEntry>;
    transform_function : Oracle.TransformFunction;
  };

  public func migration(old : {
    version : Nat;
    var zone_members : CacheV412;
  }) : {
    var zone_members : MemberCache.Cache;
  } {
    ignore old.version;
    {
      var zone_members = {
        zone_id = old.zone_members.zone_id;
        rpc_host = old.zone_members.rpc_host;
        rpc_path = old.zone_members.rpc_path;
        zone_members = old.zone_members.zone_members;
        transform_function = old.zone_members.transform_function;
        call_token = null;
      };
    };
  };
};
