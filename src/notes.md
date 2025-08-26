__motoko_runtime_information : () -> {
    compilerVersion : Text;
    rtsVersion : Text;
    garbageCollector : Text;
    sanityChecks : Nat;
    memorySize : Nat;
    heapSize : Nat;
    totalAllocation : Nat;
    reclaimed : Nat;
    maxLiveSize : Nat;
    stableMemorySize : Nat;
    logicalStableMemorySize : Nat;
    maxStackSize : Nat;
    callbackTableCount : Nat;
    callbackTableSize : Nat;
}

https://github.com/letmejustputthishere/icrc7_launchpad/blob/main/backend/factory.mo

https://github.com/dfinity/portal/pull/5574

https://github.com/dfinity/cycles-ledger/blob/main/cycles-ledger/cycles-ledger.did