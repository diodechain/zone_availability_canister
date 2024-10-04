import Blob "mo:base/Blob";
import {test; suite} "mo:test/async";
import { WriteableBand } "../src/";

actor {
  public func runTests() : async () {
    await suite("Add Blob", func() : async () {
      var band = WriteableBand.new();

      await test("Should add a blob", func() : async () {
        WriteableBand.appendBlob(band, Blob.fromArray([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
        assert band.end == 10;
        // assert band.end == 11;
      });
    });
  }
}

