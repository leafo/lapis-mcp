-- Contract tests for an OAuth grant store. Run them from your own busted spec
-- against the store you pass as oauth.grants, so a store that doesn't satisfy
-- the contract fails in your test suite rather than in production:
--
--   import grant_store_behaviour from require "lapis.mcp.oauth.grant_store_contract"
--
--   describe "McpGrants", ->
--     grant_store_behaviour (-> require("models").McpGrants), {
--       owner_values: -> { user_id: factory.Users!.id }
--     }
--
-- A grant store is any object with these methods. lapis-mcp calls nothing
-- else, and passes only SHA-256 hashes of codes and tokens (64 hex
-- characters), never plaintext:
--
--   store\owner_values(user) -> table
--     The values that record who approved a grant, given the object returned
--     by the current_user callback. lapis-mcp merges them into
--     create_for_code's values and never reads them back.
--
--   store\create_for_code(values, code_ttl) -> grant
--     values: the owner values plus client_id, client_name, redirect_uri,
--     code_challenge, resource and code_hash. The code expires code_ttl
--     seconds from now.
--
--   store\redeem_code(code_hash, tokens) -> grant | nil
--     Clears the code and sets the tokens. Returns the grant at most once per
--     code, and nil for an unknown or expired code.
--
--   store\find_by_access(access_hash) -> grant | nil
--     nil for an unknown or expired access token.
--
--   grant\delete!
--     Removes the grant, its tokens stop working.
--
-- tokens is {:access_hash, :access_ttl}, with the ttl in seconds from now.
-- There are no refresh tokens: when the access token expires the user
-- connects again. A grant exposes client_id, client_name, redirect_uri,
-- code_challenge and resource as fields.
--
-- redeem_code must be atomic, or two concurrent requests can both redeem the
-- same code. With a database, use a single conditional
-- UPDATE ... WHERE code_hash = ? ... RETURNING rather than a SELECT followed
-- by an UPDATE. These tests run one request at a time,
-- so they can't check this.

rand = require "openssl.rand"
import sha256_hex from require "lapis.mcp.oauth.util"

-- a random value shaped like the SHA-256 hashes lapis-mcp passes
random_hash = -> sha256_hex rand.bytes 32

grant_store_behaviour = (get_store, opts={}) ->
  import describe, it, before_each, assert from require "busted"

  owner_values = opts.owner_values or -> {}

  local store

  before_each ->
    store = get_store!

  create_grant = (overrides={}, code_ttl=60) ->
    values = owner_values!
    values.client_id = "https://client.example/metadata.json"
    values.client_name = "Example Client"
    values.redirect_uri = "http://localhost:3000/callback"
    values.code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    values.resource = "https://server.example/mcp"
    values.code_hash = random_hash!

    for k, v in pairs overrides
      values[k] = v

    store\create_for_code(values, code_ttl), values

  new_tokens = (overrides={}) ->
    tokens = {
      access_hash: random_hash!
      access_ttl: 3600
    }
    for k, v in pairs overrides
      tokens[k] = v
    tokens

  -- creates a grant and redeems its code
  connected_grant = (token_overrides, grant_overrides) ->
    _, values = create_grant grant_overrides
    tokens = new_tokens token_overrides
    grant = store\redeem_code values.code_hash, tokens
    assert grant, "expected redeem_code to return the grant"
    grant, tokens

  describe "grant store contract", ->
    describe "create_for_code", ->
      it "returns a grant with the request fields", ->
        grant = create_grant!
        assert.truthy grant
        assert.same "https://client.example/metadata.json", grant.client_id
        assert.same "Example Client", grant.client_name
        assert.same "http://localhost:3000/callback", grant.redirect_uri
        assert.same "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", grant.code_challenge
        assert.same "https://server.example/mcp", grant.resource

    describe "redeem_code", ->
      it "returns the grant once", ->
        _, values = create_grant!
        grant = store\redeem_code values.code_hash, new_tokens!
        assert.truthy grant
        assert.same values.client_id, grant.client_id
        assert.same values.redirect_uri, grant.redirect_uri

        assert.falsy store\redeem_code values.code_hash, new_tokens!

      it "returns nil for an unknown code", ->
        assert.falsy store\redeem_code random_hash!, new_tokens!

      it "returns nil for an expired code", ->
        _, values = create_grant {}, -10
        assert.falsy store\redeem_code values.code_hash, new_tokens!

      it "doesn't make the tokens of another redemption usable", ->
        _, values = create_grant!
        tokens = new_tokens!
        store\redeem_code values.code_hash, tokens

        second = new_tokens!
        store\redeem_code values.code_hash, second
        assert.falsy store\find_by_access second.access_hash
        assert.truthy store\find_by_access tokens.access_hash

    describe "find_by_access", ->
      it "finds a grant by its access token", ->
        grant, tokens = connected_grant!
        found = store\find_by_access tokens.access_hash
        assert.truthy found
        assert.same grant.client_id, found.client_id

      it "returns nil for an unknown access token", ->
        assert.falsy store\find_by_access random_hash!

      it "returns nil for an expired access token", ->
        _, tokens = connected_grant access_ttl: -10
        assert.falsy store\find_by_access tokens.access_hash

      it "keeps grants apart", ->
        _, first = connected_grant nil, redirect_uri: "http://localhost:1111/callback"
        _, second = connected_grant nil, redirect_uri: "http://localhost:2222/callback"
        assert.same "http://localhost:1111/callback", (store\find_by_access first.access_hash).redirect_uri
        assert.same "http://localhost:2222/callback", (store\find_by_access second.access_hash).redirect_uri

    describe "delete", ->
      it "revokes the grant's tokens", ->
        grant, tokens = connected_grant!
        grant\delete!
        assert.falsy store\find_by_access tokens.access_hash

      it "leaves other grants alone", ->
        grant = connected_grant!
        _, other = connected_grant!
        grant\delete!
        assert.truthy store\find_by_access other.access_hash

{ :grant_store_behaviour }
