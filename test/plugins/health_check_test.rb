# test/plugins/health_check_test.rb
require_relative '../test_helper'


class DummyHandler
  def self.call(request, params)
    "Not health check"
  end
end

class HealthCheckTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET')
    {
      method: method,
      path: path,
      domain: 'example.com',
      headers: {},
      body: ''
    }
  end
  
  # Test: Basic health check
  def test_basic_health_check
    health = Aris::Plugins::HealthCheck.build
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/health'))
    
    assert_equal 200, result[:status]
    assert_equal 'application/json', result[:headers]['content-type']
    
    response = JSON.parse(result[:body].first)
    assert_equal 'ok', response['status']
    assert_equal 'app', response['name']
    assert response['timestamp']
  end
  
  # Test: With custom checks
  def test_with_checks
    health = Aris::Plugins::HealthCheck.build(
      checks: {
        database: -> { true },
        redis: -> { true }
      }
    )
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/health'))
    
    assert_equal 200, result[:status]
    
    response = JSON.parse(result[:body].first)
    assert_equal 'ok', response['status']
    assert_equal 'ok', response['checks']['database']
    assert_equal 'ok', response['checks']['redis']
  end
  
  # Test: Failing check
  def test_failing_check
    health = Aris::Plugins::HealthCheck.build(
      checks: {
        database: -> { true },
        redis: -> { false }
      }
    )
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/health'))
    
    assert_equal 503, result[:status]
    
    response = JSON.parse(result[:body].first)
    assert_equal 'degraded', response['status']
    assert_equal 'ok', response['checks']['database']
    assert_equal 'fail', response['checks']['redis']
  end
  
  # Test: Check raises exception
  def test_check_exception
    health = Aris::Plugins::HealthCheck.build(
      checks: {
        database: -> { raise "Connection failed" }
      }
    )
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/health'))
    
    assert_equal 503, result[:status]
    
    response = JSON.parse(result[:body].first)
    assert_equal 'degraded', response['status']
    assert_match /error: Connection failed/, response['checks']['database']
  end
  
  # Test: Custom path
  def test_custom_path
    health = Aris::Plugins::HealthCheck.build(path: '/status')
    
    Aris.routes({
      "example.com": {
        "/status": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    # /health should not match
    result = @app.call(**build_env('/health'))
    assert_equal 404, result[:status]
    
    # /status should match
    result = @app.call(**build_env('/status'))
    assert_equal 200, result[:status]
    
    response = JSON.parse(result[:body].first)
    assert_equal 'ok', response['status']
  end
  
  # Test: Custom name and version
  def test_custom_name_and_version
    health = Aris::Plugins::HealthCheck.build(
      name: 'my-api',
      version: '1.2.3'
    )
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/health'))
    
    response = JSON.parse(result[:body].first)
    assert_equal 'my-api', response['name']
    assert_equal '1.2.3', response['version']
  end
  
  # Test: Only GET method
  def test_only_get_method
    health = Aris::Plugins::HealthCheck.build
    
    Aris.routes({
      "example.com": {
        "/health": { 
          get: { to: health, use: [health] },
          post: { to: DummyHandler }  # POST goes to different handler
        },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    # POST should go to DummyHandler, not health check
    result = @app.call(**build_env('/health', method: 'POST'))
    assert_equal 200, result[:status]
    assert_equal "Not health check", result[:body].first
  end
  
  # Test: Does not interfere with other routes
  def test_does_not_interfere
    health = Aris::Plugins::HealthCheck.build
    
    Aris.routes({
      "example.com": {
        "/health": { get: { to: health, use: [health] } },
        "/data": { get: { to: DummyHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 200, result[:status]
    assert_equal "Not health check", result[:body].first
  end
end