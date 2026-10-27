-- Runs the grant store contract against OauthGrantModel on a real Postgres
-- table. Needs a database named lapis_mcp_test (or LAPIS_MCP_TEST_DB), and is
-- marked pending when it can't connect.

config = require "lapis.config"

TEST_DB = os.getenv("LAPIS_MCP_TEST_DB") or "lapis_mcp_test"

-- the spec drops and recreates mcp_grants, so never point it at a real database
assert TEST_DB\match("test"), "LAPIS_MCP_TEST_DB must name a test database (its name must contain \"test\"), got #{TEST_DB}"

config "test", ->
  logging {
    queries: false
  }

  postgres {
    backend: "pgmoon"
    database: TEST_DB
    host: os.getenv "PGHOST"
    user: os.getenv "PGUSER"
    password: os.getenv "PGPASSWORD"
  }

import push, pop from require "lapis.environment"
import use_test_env from require "lapis.spec"
import grant_store_behaviour from require "lapis.mcp.oauth.grant_store_contract"
import OauthGrantModel from require "lapis.mcp.oauth.grant_model"

db_available = ->
  push "test"
  ok = pcall -> require("lapis.db").query "SELECT 1"
  pop!
  ok

class McpGrants extends OauthGrantModel
  @owner_values: (user) => { user_id: user.id }

-- the schema from the grant_model.moon header comment, plus the owner column
create_grants_table = ->
  schema = require "lapis.db.schema"
  import create_table, create_index, drop_table, types from schema
  import serial, text, time, foreign_key from types

  drop_table "mcp_grants" if schema.entity_exists "mcp_grants"

  create_table "mcp_grants", {
    {"id", serial}
    {"user_id", foreign_key}
    {"client_id", text}
    {"client_name", text}
    {"redirect_uri", text}
    {"code_challenge", text}
    {"resource", text}
    {"code_hash", text null: true}
    {"code_expires_at", time null: true}
    {"access_hash", text null: true}
    {"access_expires_at", time null: true}
    {"last_used_at", time null: true}
    {"created_at", time}
    {"updated_at", time}
    "PRIMARY KEY (id)"
  }
  create_index "mcp_grants", "code_hash", unique: true, where: "code_hash is not null"
  create_index "mcp_grants", "access_hash", unique: true, where: "access_hash is not null"

unless db_available!
  describe "OauthGrantModel", ->
    pending "needs a Postgres database named lapis_mcp_test"
  return

describe "OauthGrantModel", ->
  use_test_env!

  setup ->
    create_grants_table!

  before_each ->
    require("lapis.db").query "TRUNCATE mcp_grants"

  grant_store_behaviour (-> McpGrants), {
    owner_values: -> McpGrants\owner_values id: 1
  }

  it "requires subclasses to define owner_values", ->
    class Incomplete extends OauthGrantModel
    assert.has_error (-> Incomplete\owner_values {}), "Incomplete must define @owner_values(user)"

  it "stores the owner values", ->
    grant = McpGrants\create_for_code {
      user_id: 42
      client_id: "https://client.example/metadata.json"
      client_name: "Example Client"
      redirect_uri: "http://localhost:3000/callback"
      code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
      resource: "https://server.example/mcp"
      code_hash: "a"\rep 64
    }, 60

    assert.same 42, McpGrants\find(grant.id).user_id

  it "updates last_used_at only when it's stale", ->
    db = require "lapis.db"

    grant = McpGrants\create_for_code {
      user_id: 1
      client_id: "https://client.example/metadata.json"
      client_name: "Example Client"
      redirect_uri: "http://localhost:3000/callback"
      code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
      resource: "https://server.example/mcp"
      code_hash: "b"\rep 64
    }, 60

    McpGrants\redeem_code "b"\rep(64), {
      access_hash: "c"\rep 64
      access_ttl: 3600
    }

    found = McpGrants\find_by_access "c"\rep 64
    assert.is_nil found.last_used_stale
    first_used = McpGrants\find(grant.id).last_used_at
    assert.truthy first_used

    -- a recent last_used_at isn't rewritten
    McpGrants\find_by_access "c"\rep 64
    assert.same first_used, McpGrants\find(grant.id).last_used_at

    db.update "mcp_grants", {
      last_used_at: db.raw "(now() at time zone 'utc') - interval '1 hour'"
    }, id: grant.id

    McpGrants\find_by_access "c"\rep 64
    assert.not.same first_used, McpGrants\find(grant.id).last_used_at

  it "deletes expired grants", ->
    db = require "lapis.db"

    make = (code_hash, code_ttl=60) ->
      McpGrants\create_for_code {
        user_id: 1
        client_id: "https://client.example/metadata.json"
        client_name: "Example Client"
        redirect_uri: "http://localhost:3000/callback"
        code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        resource: "https://server.example/mcp"
        :code_hash
      }, code_ttl

    connect = (code_hash, access_ttl) ->
      make code_hash
      McpGrants\redeem_code code_hash, {
        access_hash: "#{code_hash}-access"
        :access_ttl
      }

    make "pending-code"
    make "expired-code", -10
    live = connect "live", 3600
    connect "expired-access", -10

    assert.same 2, McpGrants\delete_expired!

    remaining = [g.id for g in *McpGrants\select "ORDER BY id"]
    assert.same 2, #remaining
    assert.truthy McpGrants\find live.id
    assert.truthy McpGrants\find code_hash: "pending-code"
