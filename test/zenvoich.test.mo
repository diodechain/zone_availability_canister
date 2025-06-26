import Debug "mo:base/Debug";
import Time "mo:base/Time";

actor {
  public func runTests() : async () {
    Debug.print(debug_show (Time.now()));
  };
};
