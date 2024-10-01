import Array "mo:base/Array";
import Blob "mo:base/Blob";
import {test; suite; skip} "mo:test/async";
import { WriteableBand } "../src/";
import ExperimentalCycles "mo:base/ExperimentalCycles";

module {
  public func runTests() : async () {
    ExperimentalCycles.add<system>(1_000_000_000_000);

    var band = WriteableBand.new();

    await suite("Add Blob", func() : async () {
      await test("Should add a blob", func() : async () {
        WriteableBand.appendBlob(band, Blob.fromArray([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
        assert band.end == 10;
      });
    });
  };
};
