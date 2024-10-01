import Nat64 "mo:base/Nat64";
import Region "mo:base/Region";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";

module {
    let page_size : Nat64 = 65536;

    public type WriteableBand = {
        region : Region;
        var end : Nat64;
    };

    public func new() : WriteableBand {
        return {
            region = Region.new();
            var end = 0;
        };
    };

    public func capacity(wb: WriteableBand) : Nat64 {
        return Region.size(wb.region) * page_size;
    };

    private func ensureFit(wb: WriteableBand, size: Nat64) {
        while (wb.end + size > capacity(wb)) {
            if (Region.grow(wb.region, 1) == 0xFFFF_FFFF_FFFF_FFFF) {
                Debug.trap("Out of memory");
            };
            // Debug.print("Growing region " # debug_show(capacity(wb)));
        };
    };

    public func appendBlob(wb: WriteableBand, data: Blob) {
        ensureFit(wb, Nat64.fromNat(data.size()));
        Region.storeBlob(wb.region, wb.end, data);
        wb.end += Nat64.fromNat(data.size());
    };

    public func appendNat32(wb: WriteableBand, data: Nat32) {
        ensureFit(wb, 4);
        Region.storeNat32(wb.region, wb.end, data);
        wb.end += 4;
    };

    public func appendNat64(wb: WriteableBand, data: Nat64) {
        ensureFit(wb, 8);
        Region.storeNat64(wb.region, wb.end, data);
        wb.end += 8;
    };
}
