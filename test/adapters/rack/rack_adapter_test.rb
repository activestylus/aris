# rack_test.rb
# --------------------------------------------
# Tests that Rack adapter correctly:
# - Converts Rack env → Request
# - Calls PipelineRunner with correct args
# - Formats responses for Rack (array format)
# - Applies plugins through pipeline
require_relative "../../test_helper"
class HomeHandler
  def self.call(request, params)
    "Welcome Home!"
  end
end
class UserShowHandler
  def self.call(request, params)
    "User ID: #{params[:id]}, Method: #{request.method}"
  end
end
class PostHandler
  def self.call(request, params)
    { success: true, post_id: params[:id] }
  end
end
class AuthRequiredHandler
  def self.call(request, params)
    "Protected Content"
  end
end
class PipelineHandler
  def self.call(request, params)
    [202, { 'X-Pipeline-Test' => 'PASS' }, ["Accepted"]]
  end
end
class CorsHeaders
  def self.call(request, response)
    response.headers ||= {} # Ensure it's initialized if somehow nil
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['X-Custom-Req'] = 'Processed'
    nil
  end
end
class Authentication
  def self.call(request, response)
    if request.headers['HTTP_X_AUTH'] != 'VALID'
      response.status = 401
      response.body = ['Unauthorized']
      return response 
    end
    nil
  end
end
class RackAdapterTest < Minitest::Test
  def setup
    Aris::Router.define({
      "example.com": {
        use: [CorsHeaders], # Domain-level pipeline
        "/": { get: { to: HomeHandler, as: :home } },
        "/users/:id": { get: { to: UserShowHandler, as: :user } },
        "/posts/:id": { get: { to: PostHandler, as: :post, use: [CorsHeaders] } }, # Route-level use
        "/admin": {
          use: [Authentication], # Scope-level pipeline
          "/protected": { get: { to: AuthRequiredHandler, as: :admin_protected } }
        },
        "/bypass": { get: { to: PipelineHandler, as: :pipeline_bypass } } # Handler returns raw Rack
      }
    })
    @app = Aris::Adapters::RackApp.new
  end
  def build_env(path, method = 'GET', auth = nil)
    {
      'REQUEST_METHOD' => method.upcase,
      'PATH_INFO' => path,
      'QUERY_STRING' => '',
      'SERVER_NAME' => 'example.com',
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new(''),
      'HTTP_X_AUTH' => auth # Custom header for testing authentication
    }
  end
  def test_root_route_dispatch_and_defaults
    status, headers, body = @app.call(build_env('/'))
    assert_equal 200, status
    assert_equal "Welcome Home!", body.first
    assert_equal 'text/plain', headers['content-type']
  end
  def test_parameterized_route_and_request_attributes
    env = build_env('/users/42', 'GET')
    status, headers, body = @app.call(env)
    assert_equal 200, status
    assert_equal "User ID: 42, Method: GET", body.first 
  end
# test/adapters/rack/rack_adapter_test.rb - Fix the 404 test
def test_404_handling
  # Set up a custom 404 handler
  Aris.default(
    not_found: ->(req, params) { 
      [404, {'content-type' => 'text/plain'}, ["Resource not found at #{req.path_info}"]]
    }
  )
  
  Aris.routes({
    "example.com" => {
      "/" => {
        get: {
          to: ->(req, params) { [200, {}, ['Home']] }
        }
      }
    }
  })

  app = Aris::Adapters::RackApp.new
  response = app.call({
    'REQUEST_METHOD' => 'GET',
    'PATH_INFO' => '/nonexistent',
    'HTTP_HOST' => 'example.com',
    'rack.input' => StringIO.new
  })

  assert_equal 404, response[0]
  assert_equal 'Resource not found at /nonexistent', response[2].first
end
  def test_json_response_handling
    env = build_env('/posts/99', 'GET')
    status, headers, body = @app.call(env)
    assert_equal 200, status
    assert_equal 'application/json', headers['content-type']
    assert_equal '{"success":true,"post_id":"99"}', body.first
  end
  def test_raw_rack_array_bypass
    status, headers, body = @app.call(build_env('/bypass'))
    assert_equal 202, status
    assert_equal 'PASS', headers['X-Pipeline-Test']
    assert_equal ["Accepted"], body
  end
  def test_domain_level_plugin_application
    status, headers, body = @app.call(build_env('/users/10'))
    assert_equal '*', headers['Access-Control-Allow-Origin']
    assert_equal 'Processed', headers['X-Custom-Req']
  end
  def test_plugin_pipeline_halt_unauthorized
    env_unauth = build_env('/admin/protected', 'GET', 'INVALID')
    status, headers, body = @app.call(env_unauth)
    assert_equal 401, status
    assert_equal ['Unauthorized'], body
    assert_equal 'Processed', headers['X-Custom-Req'], "Headers should still be set by preceding plugin"
  end
  def test_plugin_pipeline_success
    env_auth = build_env('/admin/protected', 'GET', 'VALID')
    status, headers, body = @app.call(env_auth)
    assert_equal 200, status
    assert_equal "Protected Content", body.first
  end
  def test_scope_level_plugin_override
    status, headers, body = @app.call(build_env('/posts/1'))
    assert_equal 200, status
    assert_equal '*', headers['Access-Control-Allow-Origin']
  end
  def test_request_agnostic_accessors
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/test/data',
      'QUERY_STRING' => 'q=search&id=5',
      'HTTP_HOST' => 'example.com',
      'HTTP_VERSION' => 'HTTP/1.1',
      'OTHER_KEY' => 'ignored',
      'rack.input' => StringIO.new('{"data": 1}')
    }
    req = Aris::Adapters::Rack::Request.new(env)
    assert_equal 'POST', req.method
    assert_equal '/test/data', req.path
    assert_equal 'example.com', req.host
    assert_equal 'example.com', req.domain
    assert_equal 'q=search&id=5', req.query
    assert_equal 2, req.params.keys.size
    assert_equal '5', req.params['id']
    assert_equal '{"data": 1}', req.body
    assert req.headers.key?('HTTP_HOST')
    refute req.headers.key?('OTHER_KEY')
    refute req.headers.key?('PATH_INFO')
    assert_equal 'POST', req[:method]
    assert_equal 'example.com', req[:domain]
  end
end