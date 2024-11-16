import Blob "mo:base/Blob";
import Nat8 "mo:base/Nat8";
import Text "mo:base/Text";
import Cycles "mo:base/ExperimentalCycles";
import Types "Types";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Base16 "mo:base16/Base16";

module DiodeOracle {
    func create_request(to: Text, data: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        if (to.size() != 42) {
            Debug.trap("Invalid 'to' address size: " # debug_show (to.size()));
        };

        let request_headers = [
            { name = "Host"; value = rpc_host },
            { name = "User-Agent"; value = "diode_oracle_canister" },
            { name = "Content-Type"; value = "application/json" },
        ];

        let url = "https://" # rpc_host # rpc_path;
        let text = Text.encodeUtf8("{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"eth_call\", \"params\": [{\"to\": \"" # to # "\", \"data\": \"" # data # "\"}, \"latest\"]}");

        {
            url = url;
            max_response_bytes = null; //optional for request
            headers = request_headers;
            body = ?Blob.toArray(text);
            method = #post;
            transform = null;
        };
    };

    public func create_member_list_request(zone_id: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        // members()
        create_request(zone_id, "0x6bb04b86", rpc_host, rpc_path);
    };

    public func create_member_role_request(zone_id: Text, member_address: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        // role(address)
        let call = "0xd4322d7d000000000000000000000000" # member_address;
        create_request(zone_id, call, rpc_host, rpc_path);
    };

    public func create_identity_member_request(identity_contract_address: Text, member_address: Text, rpc_host: Text, rpc_path: Text) : Types.HttpRequestArgs {
        // IsMember(address)
        let call = "0x264560d6000000000000000000000000" # member_address;
        create_request(identity_contract_address, call, rpc_host, rpc_path);
    };

    public func http_actor() : Types.IC {
        let ic : Types.IC = actor ("aaaaa-aa");
        return ic;
    };

    public func process_http_response(http_response: Types.HttpResponsePayload) : ?Blob {
        let body = http_response.body;
        // "result":
        let needle : [Nat8] = [34, 114, 101, 115, 117, 108, 116, 34, 58, 34, 48, 120];
        Debug.print(debug_show (Text.decodeUtf8(Blob.fromArray(body))));
        let begin = search(body, 0, needle, 0);
        if (begin == 0) {
            null
        } else {
            let end = Array.nextIndexOf<Nat8>(34, body, begin, Nat8.equal);
            
            switch (end) {
                case null { null };
                case (?end) {
                    let result = Iter.toArray(Array.slice<Nat8>(body, begin + 1, end));
                    switch (Text.decodeUtf8(Blob.fromArray(result))) {
                        case (null) { null };
                        case (?text) { Base16.decode(text) };
                    };
                };
            };
        };
    };

    func search(body: [Nat8], body_start: Nat, needle: [Nat8], search_start: Nat) : Nat {
        if (body_start >= body.size()) {
            return 0;
        };
        if (body[body_start] == needle[search_start]) {
            if (search_start + 1 == needle.size()) {
                return body_start;
            } else {
                search(body, body_start + 1, needle, search_start + 1);
            };
        } else {
            search(body, body_start + 1, needle, 0);
        };
    };

    func blob_to_nat(blob: Blob) : Nat {
        let array = Blob.toArray(blob);
        let number = Array.foldLeft<Nat8, Nat>(array, 0, func (acc, byte) { acc * 256 + Nat8.toNat(byte) });
        number;
    };

    
    public func get_zone_member_role(zone_id: Text, member_address: Text, rpc_host: Text, rpc_path: Text) : async Nat {
        let request = create_member_role_request(zone_id, member_address, rpc_host, rpc_path);
        Cycles.add<system>(20_949_972_000);
        let response = await http_actor().http_request(request);
        switch (process_http_response(response)) {
            case (null) { 0 };
            case (?blob) { blob_to_nat(blob) };
        };
    };
    
    public func is_identity_member(identity_contract_address: Text, member_address: Text, rpc_host: Text, rpc_path: Text) : async Bool {
        let request = create_identity_member_request(identity_contract_address, member_address, rpc_host, rpc_path);
        Cycles.add<system>(20_949_972_000);
        let response = await http_actor().http_request(request);
        switch (process_http_response(response)) {
            case (null) { false };
            case (?blob) { blob_to_nat(blob) == 1 };
        };
    };
};
