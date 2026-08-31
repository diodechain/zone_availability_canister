import MemberCache "./MemberCache";
import ZoneAvailabilityMigration "./ZoneAvailabilityMigration";

// Same 414→415 cache migration as ZoneAvailabilityMigration, for canisters
// that already dropped the stable `version` field via a prior upgrade.
module ZoneAvailabilityVersionMigration {
  public type CacheV414 = ZoneAvailabilityMigration.CacheV414;

  public func migration(old : {
    var zone_members : CacheV414;
  }) : {
    var zone_members : MemberCache.Cache;
  } {
    ZoneAvailabilityMigration.migration(old);
  };
};
