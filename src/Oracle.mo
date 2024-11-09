import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Cycles "mo:base/ExperimentalCycles";
import Types "Types";

module DiodeOracle {

    func create_zone_request(zone_id: Text, data: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        let request_headers = [
            { name = "Host"; value = rpc_host },
            { name = "User-Agent"; value = "diode_oracle_canister" },
        ];

        let url = "https://" # rpc_host # rpc_path;

        {
            url = url;
            max_response_bytes = null; //optional for request
            headers = request_headers;
            body = ?Blob.toArray(Text.encodeUtf8("{ 
                \"jsonrpc\": \"2.0\", 
                \"id\": 1, 
                \"method\": \"eth_call\", 
                \"params\": [{\"to\": \"" # zone_id # "\", \"data\": \"" # data # "\"}, \"latest\"]
            "));
            method = #post;
            transform = null;
        };
    };

    public func create_member_list_request(zone_id: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        create_zone_request(zone_id, "0x6bb04b86", rpc_host, rpc_path);
    };

    public func create_member_role_request(zone_id: Text, member_address: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        let call = "0xd4322d7d000000000000000000000000" # member_address;
        create_zone_request(zone_id, call, rpc_host, rpc_path);
    };

    public func http_actor() : Types.IC {
        let ic : Types.IC = actor ("aaaaa-aa");
        return ic;
    };

    public func process_http_response(http_response: Types.HttpResponsePayload) : [Nat8] {
        return http_response.body;
    };

  public func get_zone_members(zone_id: Text, rpc_host: Text, rpc_path: Text) : async Types.HttpResponsePayload {
    let request = create_member_list_request(zone_id, rpc_host, rpc_path);
    Cycles.add<system>(20_949_972_000);
    let response = await http_actor().http_request(request);
    return response;
  };

};
