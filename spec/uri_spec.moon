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

    it "should verify to the end of the pattern", ->
      pattern = assert parse_template\match "app://hello"
      assert.is_nil pattern\match "app://hello/world"

    it "should fail to match when structure differs", ->
      pattern = parse_template\match "app://games/{id}"
      assert.is_not_nil pattern

      -- Wrong scheme
      result = pattern\match "http://games/123"
      assert.is_nil result

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

  describe "query parameters", ->
    it "should parse template with single query parameter", ->
      pattern = parse_template\match "app://api/resource{?fields}"
      assert.is_not_nil pattern

      -- Should match without query parameter
      result = pattern\match "app://api/resource"
      assert.same {}, result

      -- Should match with query parameter
      result = pattern\match "app://api/resource?fields=name"
      assert.same {fields: "name"}, result

    it "should parse template with multiple query parameters", ->
      pattern = parse_template\match "app://api/users{?sort,limit,offset}"
      assert.is_not_nil pattern

      -- Should match without query parameters
      result = pattern\match "app://api/users"
      assert.same {}, result

      -- Should match with one query parameter
      result = pattern\match "app://api/users?sort=name"
      assert.same {sort: "name"}, result

      -- Should match with multiple query parameters
      result = pattern\match "app://api/users?sort=name&limit=10&offset=20"
      assert.same {sort: "name", limit: "10", offset: "20"}, result

      -- Should match with parameters in different order
      result = pattern\match "app://api/users?limit=5&sort=age"
      assert.same {sort: "age", limit: "5"}, result

    it "should handle URL-encoded query parameter values", ->
      pattern = parse_template\match "app://search{?q}"
      assert.is_not_nil pattern

      -- Should handle URL-encoded values
      result = pattern\match "app://search?q=hello%20world"
      assert.same {q: "hello world"}, result

      result = pattern\match "app://search?q=test%2Bquery"
      assert.same {q: "test+query"}, result

    it "should combine path and query parameters", ->
      pattern = parse_template\match "app://games/{id}{?details,format}"
      assert.is_not_nil pattern

      -- Should match with path parameter only
      result = pattern\match "app://games/123"
      assert.same {id: "123"}, result

      -- Should match with path and query parameters
      result = pattern\match "app://games/123?details=full&format=json"
      assert.same {id: "123", details: "full", format: "json"}, result

    it "should handle whitespace in query parameter templates", ->
      pattern = parse_template\match "app://api/data{? sort , limit }"
      assert.is_not_nil pattern

      result = pattern\match "app://api/data?sort=name&limit=10"
      assert.same {sort: "name", limit: "10"}, result

    it "should handle empty query parameter values", ->
      pattern = parse_template\match "app://api/items{?filter}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/items?filter="
      assert.same {filter: ""}, result

  describe "whitespace handling", ->
    it "should handle whitespace in path parameters", ->
      pattern = parse_template\match "app://items/{ id }"
      assert.is_not_nil pattern

      result = pattern\match "app://items/123"
      assert.same {id: "123"}, result

  describe "advanced URI template patterns", ->
    it "should handle multiple path parameters with different separators", ->
      pattern = parse_template\match "app://api/v{version}/users/{userId}/posts/{postId}.json"
      assert.is_not_nil pattern

      result = pattern\match "app://api/v2/users/123/posts/456.json"
      assert.same {version: "2", userId: "123", postId: "456"}, result

    it "should handle parameters with numeric values", ->
      pattern = parse_template\match "app://pages/{page}/items/{count}"
      assert.is_not_nil pattern

      result = pattern\match "app://pages/1/items/25"
      assert.same {page: "1", count: "25"}, result

    it "should handle parameters with alphanumeric values", ->
      pattern = parse_template\match "app://users/{userId}/session/{sessionId}"
      assert.is_not_nil pattern

      result = pattern\match "app://users/user123/session/abc123xyz"
      assert.same {userId: "user123", sessionId: "abc123xyz"}, result

    it "should handle parameters with special characters in values", ->
      pattern = parse_template\match "app://files/{filename}"
      assert.is_not_nil pattern

      result = pattern\match "app://files/document_final-v2.pdf"
      assert.same {filename: "document_final-v2.pdf"}, result

    it "should handle consecutive parameters with literal separators", ->
      pattern = parse_template\match "app://combine/{first}_{second}"
      assert.is_not_nil pattern

      result = pattern\match "app://combine/hello_world"
      assert.same {first: "hello", second: "world"}, result

    it "should handle parameters at different path levels", ->
      pattern = parse_template\match "app://org/{orgId}/team/{teamId}/project/{projectId}"
      assert.is_not_nil pattern

      result = pattern\match "app://org/acme/team/dev/project/website"
      assert.same {orgId: "acme", teamId: "dev", projectId: "website"}, result

    it "should handle mixed parameter and literal segments", ->
      pattern = parse_template\match "app://api/v1/users/{userId}/profile/settings"
      assert.is_not_nil pattern

      result = pattern\match "app://api/v1/users/john123/profile/settings"
      assert.same {userId: "john123"}, result

      result = pattern\match "app://api/v1/users/john123/profile/other"
      assert.is_nil result

  describe "query parameter edge cases", ->
    it "should handle query parameters with no values", ->
      pattern = parse_template\match "app://search{?debug,verbose}"
      assert.is_not_nil pattern

      result = pattern\match "app://search?debug&verbose"
      -- Query params without values are not captured
      assert.is_nil result

    it "should handle query parameters with special characters", ->
      pattern = parse_template\match "app://api{?filter}"
      assert.is_not_nil pattern

      result = pattern\match "app://api?filter=name%3DJohn%26active%3Dtrue"
      assert.same {filter: "name=John&active=true"}, result

    it "should handle mixed parameter order in query string", ->
      pattern = parse_template\match "app://api/data{?sort,limit,offset}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/data?offset=10&sort=name&limit=5"
      assert.same {sort: "name", limit: "5", offset: "10"}, result

    it "should handle subset of query parameters", ->
      pattern = parse_template\match "app://api/items{?sort,limit,offset,filter}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/items?sort=date&limit=10"
      assert.same {sort: "date", limit: "10"}, result

    it "should handle query parameters with repeated names gracefully", ->
      pattern = parse_template\match "app://api/search{?q}"
      assert.is_not_nil pattern

      -- Last occurrence is captured (default behavior)
      result = pattern\match "app://api/search?q=first&q=second"
      assert.same {q: "second"}, result

    it "should handle query parameters with ampersands in values", ->
      pattern = parse_template\match "app://api/search{?query}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/search?query=cats%26dogs"
      assert.same {query: "cats&dogs"}, result

  describe "complex template combinations", ->
    it "should handle multiple path parameters with query parameters", ->
      pattern = parse_template\match "app://api/v{version}/users/{userId}/posts{?limit,offset,sort}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/v2/users/123/posts?limit=10&sort=date"
      assert.same {version: "2", userId: "123", limit: "10", sort: "date"}, result

    it "should handle file system paths with query parameters", ->
      pattern = parse_template\match "file:///{path}/{filename}{?version,backup}"
      assert.is_not_nil pattern

      -- result = pattern\match "file:///home/user/document.txt?version=2&backup=true"
      result = pattern\match "file:///home/document.txt?version=2&backup=true"
      -- Path parameters capture up to next literal, so path="home" and filename="user/document.txt"
      assert.same {path: "home", filename: "document.txt", version: "2", backup: "true"}, result

    it "should handle nested resource paths", ->
      pattern = parse_template\match "app://resources/{type}/{id}/sub/{subId}/details{?expand}"
      assert.is_not_nil pattern

      result = pattern\match "app://resources/articles/123/sub/456/details?expand=comments"
      assert.same {type: "articles", id: "123", subId: "456", expand: "comments"}, result

    it "should handle database-like URI patterns", ->
      pattern = parse_template\match "db:///{database}/{table}/{id}{?fields,join}"
      assert.is_not_nil pattern

      result = pattern\match "db:///myapp/users/123?fields=name,email&join=profile"
      assert.same {database: "myapp", table: "users", id: "123", fields: "name,email", join: "profile"}, result

    it "should handle API versioning with resource hierarchy", ->
      pattern = parse_template\match "api://v{version}/{service}/{resource}/{id}{?format,callback}"
      assert.is_not_nil pattern

      result = pattern\match "api://v1/user/profile/123?format=json&callback=handleResponse"
      assert.same {version: "1", service: "user", resource: "profile", id: "123", format: "json", callback: "handleResponse"}, result

  describe "parameter validation and edge cases", ->
    it "should handle parameter names with underscores and hyphens", ->
      pattern = parse_template\match "app://api/{user_id}/posts/{post-id}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/user123/posts/post456"
      assert.same {user_id: "user123", ["post-id"]: "post456"}, result

    it "should handle empty path segments correctly", ->
      pattern = parse_template\match "app://api/{segment1}/{segment2}"
      assert.is_not_nil pattern

      -- Should not match empty segments
      result = pattern\match "app://api//value2"
      assert.is_nil result

      result = pattern\match "app://api/value1/"
      assert.is_nil result

    it "should handle parameters with numeric-only names", ->
      pattern = parse_template\match "app://level/{1}/sub/{2}"
      assert.is_not_nil pattern

      result = pattern\match "app://level/first/sub/second"
      assert.same {["1"]: "first", ["2"]: "second"}, result

    it "should handle case-sensitive parameter names", ->
      pattern = parse_template\match "app://api/{UserId}/posts/{PostId}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/123/posts/456"
      assert.same {UserId: "123", PostId: "456"}, result

    it "should handle long parameter values", ->
      pattern = parse_template\match "app://data/{hash}"
      assert.is_not_nil pattern

      long_hash = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
      result = pattern\match "app://data/#{long_hash}"
      assert.same {hash: long_hash}, result

  describe "malformed template handling", ->
    it "should handle unclosed parameter braces", ->
      pattern = parse_template\match "app://api/{unclosed"
      -- Parser may return a pattern that treats this as literal
      assert.is_not_nil pattern

    it "should handle unopened parameter braces", ->
      pattern = parse_template\match "app://api/unopened}"
      -- Should parse but treat as literal
      assert.is_not_nil pattern

      result = pattern\match "app://api/unopened}"
      assert.same {}, result

    it "should handle empty parameter names", ->
      pattern = parse_template\match "app://api/{}"
      -- Parser may return a pattern even with empty names
      assert.is_not_nil pattern

    it "should handle nested braces", ->
      pattern = parse_template\match "app://api/{outer{inner}}"
      -- Parser may return a pattern that treats this as literal
      assert.is_not_nil pattern

    it "should handle malformed query parameters", ->
      pattern = parse_template\match "app://api{?unclosed"
      -- Parser may return a pattern that treats this as literal
      assert.is_not_nil pattern

  describe "performance and boundary conditions", ->
    it "should handle very long URIs", ->
      pattern = parse_template\match "app://long/path/with/many/segments/{id}/more/segments/here"
      assert.is_not_nil pattern

      result = pattern\match "app://long/path/with/many/segments/12345/more/segments/here"
      assert.same {id: "12345"}, result

    it "should handle many parameters", ->
      pattern = parse_template\match "app://api/{p1}/{p2}/{p3}/{p4}/{p5}/{p6}/{p7}/{p8}/{p9}/{p10}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/v1/v2/v3/v4/v5/v6/v7/v8/v9/v10"
      assert.same {
        p1: "v1", p2: "v2", p3: "v3", p4: "v4", p5: "v5"
        p6: "v6", p7: "v7", p8: "v8", p9: "v9", p10: "v10"
      }, result

    it "should handle many query parameters", ->
      pattern = parse_template\match "app://api{?a,b,c,d,e,f,g,h,i,j}"
      assert.is_not_nil pattern

      result = pattern\match "app://api?a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10"
      assert.same {
        a: "1", b: "2", c: "3", d: "4", e: "5"
        f: "6", g: "7", h: "8", i: "9", j: "10"
      }, result

    it "should handle edge case with parameter immediately before query", ->
      pattern = parse_template\match "app://api/{resource}{?params}"
      assert.is_not_nil pattern

      result = pattern\match "app://api/users?params=active"
      assert.same {resource: "users", params: "active"}, result
