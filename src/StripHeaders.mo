import Types "./Types";

actor class StripHeaders() {
  public shared func strip_headers(args : Types.TransformArgs) : async Types.HttpResponsePayload {
    {
      status = args.response.status;
      headers = [];
      body = args.response.body;
    };
  };
};
