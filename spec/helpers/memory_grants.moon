-- In-memory grant store for specs. Not usable in production: memory isn't
-- shared between OpenResty workers and is lost on restart.

class MemoryGrant
  new: (@store, values) =>
    for k, v in pairs values
      @[k] = v

  delete: =>
    @store.rows[@id] = nil

class MemoryGrants
  new: =>
    @rows = {}
    @next_id = 1

  owner_values: (user) => { user_id: user.id }

  find_row: (field, value, expires_field) =>
    -- a nil value would match every row where the field is unset
    return nil if value == nil

    now = os.time!
    for _, row in pairs @rows
      if row[field] == value
        return nil if expires_field and row[expires_field] <= now
        return row

    nil

  set_tokens: (row, tokens) =>
    now = os.time!
    row.access_hash = tokens.access_hash
    row.access_expires_at = now + tokens.access_ttl

  create_for_code: (values, code_ttl) =>
    row = MemoryGrant @, values
    row.id = @next_id
    row.code_expires_at = os.time! + code_ttl
    @next_id += 1
    @rows[row.id] = row
    row

  redeem_code: (code_hash, tokens) =>
    row = @find_row "code_hash", code_hash, "code_expires_at"
    return nil unless row

    row.code_hash = nil
    row.code_expires_at = nil
    @set_tokens row, tokens
    row

  find_by_access: (access_hash) =>
    @find_row "access_hash", access_hash, "access_expires_at"

{ :MemoryGrants }
