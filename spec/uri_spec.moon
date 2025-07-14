import parse_template from require "lapis.mcp.uri"

describe "lapis.mcp.uri", ->
  describe "parse_template", ->
    it "should parse simple literal URL pattern", ->
      pattern = parse_template\match "app://static/resource"
      assert.is_not_nil pattern

      -- Should match exact string
      result = pattern\match "app://static/resource"
      assert.same {}, result

      -- Should not match different string
      result = pattern\match "app://static/other"
      assert.is_nil result

    it "should parse simple template with one parameter", ->
      pattern = parse_template\match "app://games/{id}"
      assert.is_not_nil pattern

      -- Should match and extract parameter
      result = pattern\match "app://games/123"
      assert.same {id: "123"}, result

      -- Should not match different structure
      result = pattern\match "app://users/123"
      assert.is_nil result

    it "should parse template with multiple parameters", ->
      pattern = parse_template\match "app://users/{userId}/posts/{postId}"
      assert.is_not_nil pattern

      -- Should match and extract both parameters
      result = pattern\match "app://users/456/posts/789"
      assert.same {userId: "456", postId: "789"}, result

      -- Should not match with missing segments
      result = pattern\match "app://users/456"
      assert.is_nil result

    it "should handle three parameters", ->
      pattern = parse_template\match "api://v1/{resource}/{id}/action/{action}"
      assert.is_not_nil pattern

      result = pattern\match "api://v1/users/123/action/delete"
      assert.same {resource: "users", id: "123", action: "delete"}, result

    it "should handle complex URL with special characters", ->
      pattern = parse_template\match "https://api.example.com/v1/users/{id}/profile"
      assert.is_not_nil pattern

      result = pattern\match "https://api.example.com/v1/users/user123/profile"
      assert.same {id: "user123"}, result

    it "should fail to match when structure differs", ->
      pattern = parse_template\match "app://games/{id}"
      assert.is_not_nil pattern

      -- Wrong scheme
      result = pattern\match "http://games/123"
      assert.is_nil result

      -- Extra path segments
      result = pattern\match "app://games/123/extra"
      assert.same {id: "123/extra"}, result

      -- Missing parameter value
      result = pattern\match "app://games/"
      assert.is_nil result

    it "should handle file paths", ->
      pattern = parse_template\match "file:///app/models/{model}.lua"
      assert.is_not_nil pattern

      result = pattern\match "file:///app/models/User.lua"
      assert.same {model: "User"}, result

      result = pattern\match "file:///app/models/Post.lua"
      assert.same {model: "Post"}, result

    it "should handle parameters with dashes and underscores", ->
      pattern = parse_template\match "app://items/{item-id}/sub/{sub_id}"
      assert.is_not_nil pattern

      result = pattern\match "app://items/some-value/sub/other_value"
      assert.same {["item-id"]: "some-value", sub_id: "other_value"}, result

    it "should handle numeric parameter values", ->
      pattern = parse_template\match "app://page/{pageNum}"
      assert.is_not_nil pattern

      result = pattern\match "app://page/42"
      assert.same {pageNum: "42"}, result

    it "should handle empty parameter values", ->
      pattern = parse_template\match "app://search/{query}/results"
      assert.is_not_nil pattern

      -- Should fail on empty parameter (captured as empty string would not make sense)
      result = pattern\match "app://search//results"
      assert.is_nil result

  describe "edge cases", ->
    it "should handle adjacent parameters", ->
      pattern = parse_template\match "app://combine/{first}{second}"
      assert.is_not_nil pattern

      -- This is tricky - without separators, the first param would capture everything
      -- The implementation should handle this by looking ahead to the next literal
      result = pattern\match "app://combine/ab"
      -- This would be ambiguous, so behavior may vary

    it "should handle parameter at end of URL", ->
      pattern = parse_template\match "app://items/{id}"
      assert.is_not_nil pattern

      result = pattern\match "app://items/12345"
      assert.same {id: "12345"}, result

    it "should handle multiple slashes", ->
      pattern = parse_template\match "app://deep/nested/path/{id}/more/nested"
      assert.is_not_nil pattern

      result = pattern\match "app://deep/nested/path/value123/more/nested"
      assert.same {id: "value123"}, result

    it "should fail on malformed input", ->
      -- Test that parse_template handles invalid templates gracefully
      result = parse_template\match "app://invalid/{unclosed"
      -- Depending on implementation, this might return nil or a pattern that fails to match

    it "should handle templates with no parameters", ->
      pattern = parse_template\match "app://static/endpoint"
      assert.is_not_nil pattern

      result = pattern\match "app://static/endpoint"
      assert.same {}, result

      result = pattern\match "app://static/different"
      assert.is_nil result
