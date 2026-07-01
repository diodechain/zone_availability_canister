module ZoneAvailabilityVersionMigration {
  // Drops the stable version field when upgrading canisters that already have
  // MemberCache.Cache (with call_token) but still store version in stable memory.
  public func migration(_old : { version : Nat }) : {} {
    {};
  };
};
