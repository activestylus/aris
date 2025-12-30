require_relative 'test_helper'

class SuccessHandler
  def self.call(request, params)
    "Success"
  end
end
class Custom404Handler
  def self.call(request, params)
    [404, {'X-Error-Code' => 'E404'}, ["Resource not found at #{request.path}"]]
  end
end
class System500Handler
  def self.call(request, exception)
    setter = Thread.current[:error_message_setter]
    setter.call(exception.message) if setter

    # FIX: Ensure the header Hash is created fresh and correctly formatted.
    # The content-type header must be consistently set.
    [500, {'content-type' => 'text/html'}, ["System Error: #{exception.class}"]]

  end
end
class ThrowingHandler
  def self.call(request, params)
    raise "Database connection failed"
  end
end
Aris.default( not_found: Custom404Handler, error: System500Handler )
class RouterResilienceTest < Minitest::Test
  def setup
    # Re-establish handlers for EACH test
    Aris.default( not_found: Custom404Handler, error: System500Handler )
    
    
    
    Aris.routes(
      "example.com": {
        "/users/:id": { 
          get: { to: SuccessHandler, as: :user_show } 
        },
        "/fail": { 
          get: { to: ThrowingHandler } 
        }
      }
    )
    @router = Aris::Router
    @router.default_domain = "example.com"
    @app = Aris::Adapters::RackApp.new
  end
  def build_env(path, method = 'GET')
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'HTTP_HOST' => 'example.com',
      'SERVER_NAME' => 'example.com',
      'rack.input' => StringIO.new(''),
      'QUERY_STRING' => ''
    }
  end
  def test_01_non_existent_path_triggers_custom_404
    env = build_env('/nonexistent/path')
    status, headers, body = @app.call(env)
    assert_equal 404, status
    assert_equal 'E404', headers['X-Error-Code']
    assert_equal ["Resource not found at /nonexistent/path"], body
  end
  def test_02_failed_constraint_triggers_custom_404
    result = @router.match(domain: "example.com", method: :get, path: "/nonexistent")
    assert_nil result
    end
  def test_03_handler_exception_triggers_custom_500
    captured_message = nil
    setter = Proc.new { |msg| captured_message = msg }
    Thread.current[:error_message_setter] = setter
    env = build_env('/fail')
    status, headers, body = @app.call(env)
    assert_equal 500, status
    assert_equal 'text/html', headers['content-type'], "The custom 500 handler must return text/html content-type" 
    assert_equal ["System Error: RuntimeError"], body
    assert_equal "Database connection failed", captured_message, "The exception message should have been captured locally."
  ensure
    Thread.current[:error_message_setter] = nil
  end

  def test_04_redirect_helper_returns_correct_response
    status, headers, body = Aris.redirect(:user_show, id: 100)
    assert_equal 302, status
    assert_equal [], body
    assert_equal "https://example.com/users/100", headers['Location'], "Location header must contain the full URL."
    status, headers, body = Aris.redirect('/external/url')
    assert_equal 302, status
    assert_equal [], body
    assert_equal '/external/url', headers['Location']
  end
end
class ErrorHandlerEdgeCasesTest < Minitest::Test
    def setup
    Aris::Router.default_domain = "example.com"
  end
  
  def teardown
    # Don't leave the exploding handler for other tests!
    Aris::Router.set_defaults(error: nil)
  end
  def test_error_handler_that_raises
    exploding_handler = ->(req, error) { raise "Handler failed!" }
    Aris::Router.set_defaults(error: exploding_handler)
    mock_request = Minitest::Mock.new
    def mock_request.host; 'example.com'; end
    def mock_request.domain; 'example.com'; end
    def mock_request.request_method; 'GET'; end
    def mock_request.method; 'GET'; end
    def mock_request.path_info; '/test'; end
    def mock_request.path; '/test'; end
    def mock_request.query; ''; end
    def mock_request.headers; {}; end
    def mock_request.body; ''; end
    def mock_request.params; {}; end
    def mock_request.env; {}; end
    def mock_request.[](key); nil; end
    response = Aris.error(mock_request, RuntimeError.new("Original error"))

    assert_equal 500, response[0]
    assert_includes response[2].first, "Internal Server Error"
  end
end