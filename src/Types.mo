module Types {

  //1. Type that describes the Request arguments for an HTTPS outcall
  //See: https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-http_request
  public type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HttpHeader];
    body : ?[Nat8];
    method : HttpMethod;
    transform : ?TransformRawResponseFunction;
  };

  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  public type HttpMethod = {
    #get;
    #post;
    #head;
  };

  public type HttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : [Nat8];
  };

  //2. HTTPS outcalls have an optional "transform" key. These two types help describe it.
  //"The transform function may, for example, transform the body in any way, add or remove headers,
  //modify headers, etc. "
  //See: https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-http_request

  //2.1 This type describes a function called "TransformRawResponse" used in line 14 above
  //"If provided, the calling canister itself must export this function."
  //In this minimal example for a GET request, we declare the type for completeness, but
  //we do not use this function. We will pass "null" to the HTTP request.
  public type TransformRawResponseFunction = {
    function : shared query TransformArgs -> async HttpResponsePayload;
    context : Blob;
  };

  //2.2 This type describes the arguments the transform function needs
  public type TransformArgs = {
    response : HttpResponsePayload;
    context : Blob;
  };

  public type CanisterHttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : [Nat8];
  };

  public type TransformContext = {
    function : shared query TransformArgs -> async HttpResponsePayload;
    context : Blob;
  };

  //3. Declaring the IC management canister which we use to make the HTTPS outcall
  public type IC = actor {
    http_request : HttpRequestArgs -> async HttpResponsePayload;
    ecdsa_public_key : EcdsaPublicKeyArgs -> async EcdsaPublicKeyResult;
  };

  public type EcdsaCurve = {
    #secp256k1;
  };

  public type EcdsaPublicKeyArgs = {
    canister_id : ?Blob;
    derivation_path : [Blob];
    key_id : { curve : EcdsaCurve; name : Text };
  };

  public type EcdsaPublicKeyResult = {
    public_key : Blob;
    chain_code : Blob;
  };
};
