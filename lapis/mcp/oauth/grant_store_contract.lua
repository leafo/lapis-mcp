local rand = require("openssl.rand")
local sha256_hex
sha256_hex = require("lapis.mcp.oauth.util").sha256_hex
local random_hash
random_hash = function()
  return sha256_hex(rand.bytes(32))
end
local grant_store_behaviour
grant_store_behaviour = function(get_store, opts)
  if opts == nil then
    opts = { }
  end
  local describe, it, before_each, assert
  do
    local _obj_0 = require("busted")
    describe, it, before_each, assert = _obj_0.describe, _obj_0.it, _obj_0.before_each, _obj_0.assert
  end
  local owner_values = opts.owner_values or function()
    return { }
  end
  local store
  before_each(function()
    store = get_store()
  end)
  local create_grant
  create_grant = function(overrides, code_ttl)
    if overrides == nil then
      overrides = { }
    end
    if code_ttl == nil then
      code_ttl = 60
    end
    local values = owner_values()
    values.client_id = "https://client.example/metadata.json"
    values.client_name = "Example Client"
    values.redirect_uri = "http://localhost:3000/callback"
    values.code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    values.resource = "https://server.example/mcp"
    values.code_hash = random_hash()
    for k, v in pairs(overrides) do
      values[k] = v
    end
    return store:create_for_code(values, code_ttl), values
  end
  local new_tokens
  new_tokens = function(overrides)
    if overrides == nil then
      overrides = { }
    end
    local tokens = {
      access_hash = random_hash(),
      access_ttl = 3600
    }
    for k, v in pairs(overrides) do
      tokens[k] = v
    end
    return tokens
  end
  local connected_grant
  connected_grant = function(token_overrides, grant_overrides)
    local _, values = create_grant(grant_overrides)
    local tokens = new_tokens(token_overrides)
    local grant = store:redeem_code(values.code_hash, tokens)
    assert(grant, "expected redeem_code to return the grant")
    return grant, tokens
  end
  return describe("grant store contract", function()
    describe("create_for_code", function()
      return it("returns a grant with the request fields", function()
        local grant = create_grant()
        assert.truthy(grant)
        assert.same("https://client.example/metadata.json", grant.client_id)
        assert.same("Example Client", grant.client_name)
        assert.same("http://localhost:3000/callback", grant.redirect_uri)
        assert.same("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", grant.code_challenge)
        return assert.same("https://server.example/mcp", grant.resource)
      end)
    end)
    describe("redeem_code", function()
      it("returns the grant once", function()
        local _, values = create_grant()
        local grant = store:redeem_code(values.code_hash, new_tokens())
        assert.truthy(grant)
        assert.same(values.client_id, grant.client_id)
        assert.same(values.redirect_uri, grant.redirect_uri)
        return assert.falsy(store:redeem_code(values.code_hash, new_tokens()))
      end)
      it("returns nil for an unknown code", function()
        return assert.falsy(store:redeem_code(random_hash(), new_tokens()))
      end)
      it("returns nil for an expired code", function()
        local _, values = create_grant({ }, -10)
        return assert.falsy(store:redeem_code(values.code_hash, new_tokens()))
      end)
      return it("doesn't make the tokens of another redemption usable", function()
        local _, values = create_grant()
        local tokens = new_tokens()
        store:redeem_code(values.code_hash, tokens)
        local second = new_tokens()
        store:redeem_code(values.code_hash, second)
        assert.falsy(store:find_by_access(second.access_hash))
        return assert.truthy(store:find_by_access(tokens.access_hash))
      end)
    end)
    describe("find_by_access", function()
      it("finds a grant by its access token", function()
        local grant, tokens = connected_grant()
        local found = store:find_by_access(tokens.access_hash)
        assert.truthy(found)
        return assert.same(grant.client_id, found.client_id)
      end)
      it("returns nil for an unknown access token", function()
        return assert.falsy(store:find_by_access(random_hash()))
      end)
      it("returns nil for an expired access token", function()
        local _, tokens = connected_grant({
          access_ttl = -10
        })
        return assert.falsy(store:find_by_access(tokens.access_hash))
      end)
      return it("keeps grants apart", function()
        local _, first = connected_grant(nil, {
          redirect_uri = "http://localhost:1111/callback"
        })
        local second
        _, second = connected_grant(nil, {
          redirect_uri = "http://localhost:2222/callback"
        })
        assert.same("http://localhost:1111/callback", (store:find_by_access(first.access_hash)).redirect_uri)
        return assert.same("http://localhost:2222/callback", (store:find_by_access(second.access_hash)).redirect_uri)
      end)
    end)
    return describe("delete", function()
      it("revokes the grant's tokens", function()
        local grant, tokens = connected_grant()
        grant:delete()
        return assert.falsy(store:find_by_access(tokens.access_hash))
      end)
      return it("leaves other grants alone", function()
        local grant = connected_grant()
        local _, other = connected_grant()
        grant:delete()
        return assert.truthy(store:find_by_access(other.access_hash))
      end)
    end)
  end)
end
return {
  grant_store_behaviour = grant_store_behaviour
}
