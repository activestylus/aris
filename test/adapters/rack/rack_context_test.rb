# rack_path.rb
require_relative "../../test_helper"
class TestHandler
  def self.call(_request, _params)
    # Returns the current domain context for testing purposes
    [200, {}, [Aris.current_domain]] 
  end
end
class OtherHandler
  def self.call(_request, _params)
    [200, {}, ["Other OK"]]
  end
end
class RackContextTest < Minitest::Test
  def setup
    Aris::Router.define({
      "api.example.com": {
        "/context": { get: { to: TestHandler, as: :api_context } },
        "/users": { get: { to: OtherHandler, as: :api_users } }
      },
      "public.example.com": {
        "/context": { get: { to: TestHandler, as: :public_context } }
      }
    })
    @app = Aris::Adapters::RackApp.new
    Aris::Router.default_domain = "public.example.com"
  end
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  def build_env(host, path = '/context', method = 'GET')
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'HTTP_HOST' => host,
      'SERVER_NAME' => host,
      'QUERY_STRING' => '',
      'rack.input' => StringIO.new('')
    }
  end
  def test_01_rack_call_sets_thread_context_correctly
    api_domain = "api.example.com"
    env = build_env(api_domain)
    refute_equal api_domain, Thread.current[:aris_current_domain]
    status, headers, body = @app.call(env)
    assert_equal api_domain, body.first, "Handler should have read the domain set by Rack"
    assert_equal 200, status
    assert_nil Thread.current[:aris_current_domain], "Thread context must be nil after request completion (thread safety)"
  end
  def test_02_context_is_isolated_during_concurrent_calls
    api_env = build_env("api.example.com", "/context")
    public_env = build_env("public.example.com", "/context")
    result1, result2 = nil, nil
    thread1 = Thread.new { result1 = @app.call(api_env)[2].first; }
    thread2 = Thread.new { result2 = @app.call(public_env)[2].first; }
    thread1.join
    thread2.join
    assert_equal "api.example.com", result1, "Thread 1 should have processed the API domain"
    assert_equal "public.example.com", result2, "Thread 2 should have processed the Public domain"
  end
  def test_03_helper_methods_use_active_rack_context
    api_domain = "api.example.com"
    env = build_env(api_domain, "/users")
    @app.call(env) 
    status, headers, body = @app.call(build_env(api_domain, "/context"))
    assert_equal api_domain, body.first 
    assert_nil Thread.current[:aris_current_domain], "Context must be clean after handler execution"
  end
end