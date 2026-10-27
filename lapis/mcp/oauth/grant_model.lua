local db = require("lapis.db")
local Model
Model = require("lapis.db.model").Model
local NOW = "(now() at time zone 'utc')"
local LAST_USED_INTERVAL = "15 minutes"
local LAST_USED_STALE = "(last_used_at IS NULL OR last_used_at < " .. tostring(NOW) .. " - interval '" .. tostring(LAST_USED_INTERVAL) .. "')"
local from_now
from_now = function(ttl)
  return db.raw(db.interpolate_query(tostring(NOW) .. " + ? * interval '1 second'", ttl))
end
local token_assigns
token_assigns = function(tokens)
  return {
    access_hash = tokens.access_hash,
    access_expires_at = from_now(tokens.access_ttl),
    refresh_hash = tokens.refresh_hash,
    refresh_expires_at = from_now(tokens.refresh_ttl),
    updated_at = db.raw(NOW)
  }
end
local update_returning
update_returning = function(model, assigns, where, ...)
  where = db.interpolate_query(where, ...)
  local res = db.query("UPDATE " .. tostring(db.escape_identifier(model:table_name())) .. " SET " .. tostring(db.encode_assigns(assigns)) .. " WHERE " .. tostring(where) .. " RETURNING *")
  local row = res[1]
  return row and model:load(row) or nil
end
local OauthGrantModel
do
  local _class_0
  local _parent_0 = Model
  local _base_0 = { }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, ...)
      return _class_0.__parent.__init(self, ...)
    end,
    __base = _base_0,
    __name = "OauthGrantModel",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.timestamp = true
  self.owner_values = function(self, user)
    return error(tostring(self.__name) .. " must define @owner_values(user)")
  end
  self.create_for_code = function(self, values, code_ttl)
    do
      local _tbl_0 = { }
      for k, v in pairs(values) do
        _tbl_0[k] = v
      end
      values = _tbl_0
    end
    values.code_expires_at = from_now(code_ttl)
    return self:create(values)
  end
  self.redeem_code = function(self, code_hash, tokens)
    local assigns = token_assigns(tokens)
    assigns.code_hash = db.NULL
    assigns.code_expires_at = db.NULL
    return update_returning(self, assigns, "code_hash = ? AND code_expires_at > " .. tostring(NOW), code_hash)
  end
  self.find_by_access = function(self, access_hash)
    local grant = self:select("WHERE access_hash = ? AND access_expires_at > " .. tostring(NOW), access_hash, {
      fields = "*, " .. tostring(LAST_USED_STALE) .. " AS last_used_stale"
    })[1]
    if not (grant) then
      return nil
    end
    local stale = grant.last_used_stale
    grant.last_used_stale = nil
    if stale then
      db.query("UPDATE " .. tostring(db.escape_identifier(self:table_name())) .. " SET last_used_at = " .. tostring(NOW) .. " WHERE id = ? AND " .. tostring(LAST_USED_STALE), grant.id)
    end
    return grant
  end
  self.rotate_refresh = function(self, refresh_hash, tokens)
    local assigns = token_assigns(tokens)
    assigns.previous_refresh_hash = db.raw("refresh_hash")
    do
      local grant = update_returning(self, assigns, "refresh_hash = ? AND refresh_expires_at > " .. tostring(NOW), refresh_hash)
      if grant then
        return grant
      end
    end
    do
      local reused = self:find({
        previous_refresh_hash = refresh_hash
      })
      if reused then
        return nil, "reused", reused
      end
    end
    return nil
  end
  self.delete_expired = function(self)
    local res = db.query("DELETE FROM " .. tostring(db.escape_identifier(self:table_name())) .. " WHERE (access_hash IS NULL AND code_expires_at < " .. tostring(NOW) .. ") OR refresh_expires_at < " .. tostring(NOW))
    return res.affected_rows
  end
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  OauthGrantModel = _class_0
end
return {
  OauthGrantModel = OauthGrantModel
}
