action = require "lapis.cmd.actions.mcp"

describe "lapis cmd mcp action", ->
  after_each ->
    package.loaded["test.fake_server"] = nil

  it "parses the server module positional alongside shared flags", ->
    parser = action.argparser!
    args = parser\parse {"test.fake_server", "--debug", "--skip-init"}

    assert.equal "test.fake_server", args.server_module
    assert.is_true args.debug
    assert.is_true args.skip_initialize

  it "instantiates the chosen server module and dispatches to it", ->
    created = {}

    class FakeServer
      new: (opts={}) =>
        created.options = opts

      run_stdio: =>
        created.run_stdio = true

    package.loaded["test.fake_server"] = FakeServer

    action[1] {}, {
      server_module: "test.fake_server"
      debug: true
    }, {
      environment: "test"
    }

    assert.is_true created.options.debug
    assert.is_true created.run_stdio
