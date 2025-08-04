import { test; suite } "mo:test/async";

// Simple test to verify execution
let _ = do {
  await test(
    "Simple test that should fail if tests are running",
    func() : async () {
      assert 1 == 2; // This should definitely fail if tests are executing
    },
  );
};