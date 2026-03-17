action = require "lapis.cmd.actions.mcp"

describe "lapis cmd mcp action", ->
  after_each ->
    package.loaded["test.fake_server"] = nil
    package.loaded["test.fake_app"] = nil

  it "parses the server module positional alongside shared flags", ->
    parser = action.argparser!
    args = parser\parse {"test.fake_server", "--debug", "--skip-init"}

    assert.equal "test.fake_server", args.server_module
    assert.is_true args.debug
    assert.is_true args.skip_initialize

  it "injects the resolved app into the server before dispatching", ->
    created = {}
    fake_app = {
      name: "fake-app"
    }

    class FakeServer
      new: (opts={}) =>
        created.options = opts

      run_stdio: =>
        created.run_stdio = true

    package.loaded["test.fake_server"] = FakeServer
    package.loaded["test.fake_app"] = fake_app

    action[1] {
      get_config: (environment) ->
        {
          app_module: "test.fake_app"
        }
    }, {
      server_module: "test.fake_server"
      debug: true
    }, {
      environment: "test"
    }

    assert.same fake_app, created.options.app
    assert.is_true created.options.debug
    assert.is_true created.run_stdio
