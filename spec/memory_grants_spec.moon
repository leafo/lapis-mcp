import MemoryGrants from require "spec.helpers.memory_grants"
import grant_store_behaviour from require "lapis.mcp.oauth.grant_store_contract"

describe "MemoryGrants", ->
  grant_store_behaviour -> MemoryGrants!
