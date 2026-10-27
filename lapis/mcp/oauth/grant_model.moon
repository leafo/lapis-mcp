-- Base Lapis model for a Postgres grant store, see
-- lapis.mcp.oauth.grant_store_contract for the interface it implements.
-- Extend it in your app, define the owner values, and create a table with at
-- least these columns and indexes (any table name):
--
--   class McpGrants extends OauthGrantModel
--     @owner_values: (user) => { user_id: user.id }
--
--   create_table "mcp_grants", {
--     {"id", serial}
--     {"client_id", text}
--     {"client_name", text}
--     {"redirect_uri", text}
--     {"code_challenge", text}
--     {"resource", text}
--     {"code_hash", text null: true}
--     {"code_expires_at", time null: true}
--     {"access_hash", text null: true}
--     {"access_expires_at", time null: true}
--     {"refresh_hash", text null: true}
--     {"previous_refresh_hash", text null: true}
--     {"refresh_expires_at", time null: true}
--     {"last_used_at", time null: true}
--     {"created_at", time}
--     {"updated_at", time}
--     "PRIMARY KEY (id)"
--   }
--   create_index "mcp_grants", "code_hash", unique: true, where: "code_hash is not null"
--   create_index "mcp_grants", "access_hash", unique: true, where: "access_hash is not null"
--   create_index "mcp_grants", "refresh_hash", unique: true, where: "refresh_hash is not null"
--   create_index "mcp_grants", "previous_refresh_hash", where: "previous_refresh_hash is not null"
--
-- plus a column for each key your owner_values returns (user_id above). Times
-- are UTC, like the timestamps Lapis models write, so the time columns must
-- be timestamp without time zone, which is what the time type creates.
--
-- Expired rows aren't removed automatically, call McpGrants\delete_expired!
-- periodically, for example from a cron job.

db = require "lapis.db"
import Model from require "lapis.db.model"

NOW = "(now() at time zone 'utc')"

-- last_used_at is only written when it's older than this, so a busy
-- connection doesn't write on every request
LAST_USED_INTERVAL = "15 minutes"
LAST_USED_STALE = "(last_used_at IS NULL OR last_used_at < #{NOW} - interval '#{LAST_USED_INTERVAL}')"

from_now = (ttl) ->
  db.raw db.interpolate_query "#{NOW} + ? * interval '1 second'", ttl

token_assigns = (tokens) ->
  {
    access_hash: tokens.access_hash
    access_expires_at: from_now tokens.access_ttl
    refresh_hash: tokens.refresh_hash
    refresh_expires_at: from_now tokens.refresh_ttl
    updated_at: db.raw NOW
  }

-- a single conditional UPDATE, so concurrent requests can't both match the
-- same row. Returns the updated row loaded as a model, or nil
update_returning = (model, assigns, where, ...) ->
  where = db.interpolate_query where, ...
  res = db.query "UPDATE #{db.escape_identifier model\table_name!} SET #{db.encode_assigns assigns} WHERE #{where} RETURNING *"
  row = res[1]
  row and model\load(row) or nil

class OauthGrantModel extends Model
  @timestamp: true

  @owner_values: (user) =>
    error "#{@__name} must define @owner_values(user)"

  @create_for_code: (values, code_ttl) =>
    values = {k, v for k, v in pairs values}
    values.code_expires_at = from_now code_ttl
    @create values

  @redeem_code: (code_hash, tokens) =>
    assigns = token_assigns tokens
    assigns.code_hash = db.NULL
    assigns.code_expires_at = db.NULL

    update_returning @, assigns,
      "code_hash = ? AND code_expires_at > #{NOW}", code_hash

  @find_by_access: (access_hash) =>
    grant = @select("WHERE access_hash = ? AND access_expires_at > #{NOW}", access_hash, {
      fields: "*, #{LAST_USED_STALE} AS last_used_stale"
    })[1]

    return nil unless grant

    stale = grant.last_used_stale
    grant.last_used_stale = nil

    -- the condition is repeated in the UPDATE so that of several concurrent
    -- requests that all saw a stale value, only the first writes
    if stale
      db.query "UPDATE #{db.escape_identifier @table_name!} SET last_used_at = #{NOW} WHERE id = ? AND #{LAST_USED_STALE}", grant.id

    grant

  @rotate_refresh: (refresh_hash, tokens) =>
    -- SET expressions read the row before the update, so the old
    -- refresh_hash is what gets remembered
    assigns = token_assigns tokens
    assigns.previous_refresh_hash = db.raw "refresh_hash"

    if grant = update_returning @, assigns, "refresh_hash = ? AND refresh_expires_at > #{NOW}", refresh_hash
      return grant

    -- checked after the update, so a concurrent request that lost the race
    -- for the same refresh token is reported as reuse too
    if reused = @find previous_refresh_hash: refresh_hash
      return nil, "reused", reused

    nil

  -- deletes grants whose code expired without being redeemed, and grants
  -- whose refresh token has expired. Returns the number of rows deleted
  @delete_expired: =>
    res = db.query "DELETE FROM #{db.escape_identifier @table_name!} WHERE (access_hash IS NULL AND code_expires_at < #{NOW}) OR refresh_expires_at < #{NOW}"
    res.affected_rows

{ :OauthGrantModel }
