# test/adapters/mock_adapter_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/adapters/mock/adapter'  # ← ADD THIS
require_relative '../../lib/aris/plugins/bearer_auth'  # ← ADD THIS
require_relative '../../lib/aris/plugins/json'         # ← ADD THIS

class MockAdapterTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "test.com"
    
    # Define routes with a plugin
    Aris.routes({
      "test.com": {
        "/hello": {
          get: { 
            to: ->(request, params) { "Hello from Mock!" }
          }
        },
        "/json": {
          get: {
            to: ->(request, params) { { message: "json response" } }
          }
        },
        "/params/:id": {
          get: {
            to: ->(request, params) { "ID: #{params[:id]}" }
          }
        }
      }
    })
    
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def test_basic_get_request
    result = @app.call(
      method: 'GET',
      path: '/hello',
      domain: 'test.com'
    )
    
    assert_equal 200, result[:status]
    assert_equal ['Hello from Mock!'], result[:body]
  end
  
  def test_json_response
    result = @app.call(
      method: 'GET',
      path: '/json',
      domain: 'test.com'
    )
    
    assert_equal 200, result[:status]
    assert_equal 'application/json', result[:headers]['content-type']
    assert_includes result[:body].first, 'json response'
  end
  
  def test_path_parameters
    result = @app.call(
      method: 'GET',
      path: '/params/123',
      domain: 'test.com'
    )
    
    assert_equal 200, result[:status]
    assert_equal ['ID: 123'], result[:body]
  end
  
  def test_404_handling
    result = @app.call(
      method: 'GET',
      path: '/nonexistent',
      domain: 'test.com'
    )
    
    assert_equal 404, result[:status]
  end

  def test_plugin_works_with_mock_adapter
    # Use instance directly with config
    bearer_plugin = Aris::Plugins::BearerAuth.build(token: 'secret123')
    
    Aris.routes({
      "test.com": {
        use: [bearer_plugin],  # ← Instance, not symbol
        "/protected": {
          get: {
            to: ->(request, params) { "Protected data" }
          }
        }
      }
    })
    
    # Test without token - should get 401
    result = @app.call(
      method: 'GET',
      path: '/protected',
      domain: 'test.com',
      headers: {}
    )
    
    assert_equal 401, result[:status]
    
    # Test with valid token - should succeed
    result = @app.call(
      method: 'GET',
      path: '/protected',
      domain: 'test.com',
      headers: { 'HTTP_AUTHORIZATION' => 'Bearer secret123' }
    )
    
    assert_equal 200, result[:status]
    assert_equal ['Protected data'], result[:body]
  end
  
  def test_json_plugin_with_mock_adapter
    # Json plugin uses symbol and class directly (no build needed)
    Aris.routes({
      "test.com": {
        use: [:json],  # ← USE SYMBOL FROM REGISTRY
        "/api/data": {
          post: {
            to: ->(request, params) { 
              "Received: #{request.json_body['name']}" 
            }
          }
        }
      }
    })
    
    result = @app.call(
      method: 'POST',
      path: '/api/data',
      domain: 'test.com',
      headers: { 'HTTP_CONTENT_TYPE' => 'application/json' },
      body: '{"name":"Alice"}'
    )
    
    assert_equal 200, result[:status]
    assert_equal ['Received: Alice'], result[:body]
  end
end