# test/plugins/cors_test.rb
require_relative '../test_helper'

class CorsHandler
  def self.call(request, params)
    { message: 'Success' }.to_json
  end
end

class CorsTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "api.example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET', origin: nil)
    headers = {}
    headers['HTTP_ORIGIN'] = origin if origin
    
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'api.example.com',
      headers: headers,
      body: ''
    }
  end
  
  def test_wildcard_origins_allow_all
    cors = Aris::Plugins::Cors.build(origins: '*')
    Aris.routes({"api.example.com": {use: [cors],"/data": { get: { to: CorsHandler } }}})
    result = @app.call(**build_env('/data', origin: 'https://example.com'))
    assert_equal 200, result[:status]
    assert_equal '*', result[:headers]['Access-Control-Allow-Origin']
    assert result[:headers]['Access-Control-Allow-Methods']
  end

  def test_specific_origin_allowed
    cors = Aris::Plugins::Cors.build(origins: ['https://app.example.com', 'https://admin.example.com'])
    Aris.routes({"api.example.com": {use: [cors],"/data": { get: { to: CorsHandler } }}})
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    assert_equal 200, result[:status]
    assert_equal 'https://app.example.com', result[:headers]['Access-Control-Allow-Origin']
  end

  def test_disallowed_origin_no_headers
    cors = Aris::Plugins::Cors.build(origins: ['https://app.example.com'])
    Aris.routes({"api.example.com": {use: [cors],"/data": { get: { to: CorsHandler } }}})
    result = @app.call(**build_env('/data', origin: 'https://evil.com'))
    assert_equal 200, result[:status]
    refute result[:headers].key?('Access-Control-Allow-Origin')
  end

  def test_no_origin_header_skips_cors
    cors = Aris::Plugins::Cors.build(origins: '*')
    Aris.routes({"api.example.com": {use: [cors],"/data": { get: { to: CorsHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 200, result[:status]
    refute result[:headers].key?('Access-Control-Allow-Origin')
  end

  def test_preflight_request_returns_204
    cors = Aris::Plugins::Cors.build(origins: '*')
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { 
          post: { to: CorsHandler },
          options: { to: CorsHandler }
        }
      }
    })
    result = @app.call(**build_env('/data', method: 'OPTIONS', origin: 'https://app.example.com'))
    assert_equal 204, result[:status]
    assert_equal [], result[:body]
    assert_equal '*', result[:headers]['Access-Control-Allow-Origin']
    assert result[:headers]['Access-Control-Allow-Methods']
    assert result[:headers]['Access-Control-Max-Age']
  end
  def test_custom_methods
    cors = Aris::Plugins::Cors.build(origins: '*', methods: ['GET', 'POST'])
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    assert_equal 'GET, POST', result[:headers]['Access-Control-Allow-Methods']
  end

  # Test: Custom headers configured
  def test_custom_headers
    cors = Aris::Plugins::Cors.build(
      origins: '*',
      headers: ['content-type', 'X-Custom-Header']
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    assert_equal 'content-type, X-Custom-Header', result[:headers]['Access-Control-Allow-Headers']
  end

  # Test: Credentials enabled
  def test_credentials_enabled
    cors = Aris::Plugins::Cors.build(
      origins: ['https://app.example.com'],
      credentials: true
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    assert_equal 'https://app.example.com', result[:headers]['Access-Control-Allow-Origin']
    assert_equal 'true', result[:headers]['Access-Control-Allow-Credentials']
  end

  # Test: Credentials with wildcard echoes origin
  def test_credentials_with_wildcard_echoes_origin
    cors = Aris::Plugins::Cors.build(
      origins: '*',
      credentials: true
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    # Must echo specific origin when credentials: true (can't use *)
    assert_equal 'https://app.example.com', result[:headers]['Access-Control-Allow-Origin']
    assert_equal 'true', result[:headers]['Access-Control-Allow-Credentials']
  end

  # Test: Custom max age
  def test_custom_max_age
    cors = Aris::Plugins::Cors.build(
      origins: '*',
      max_age: 3600
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    assert_equal '3600', result[:headers]['Access-Control-Max-Age']
  end

  # Test: Expose headers
  def test_expose_headers
    cors = Aris::Plugins::Cors.build(
      origins: '*',
      expose_headers: ['X-Total-Count', 'X-Page']
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    
    assert_equal 'X-Total-Count, X-Page', result[:headers]['Access-Control-Expose-Headers']
  end

  # Test: Multiple origins
  def test_multiple_origins
    cors = Aris::Plugins::Cors.build(
      origins: [
        'https://app.example.com',
        'https://staging.example.com',
        'https://admin.example.com'
      ]
    )
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { get: { to: CorsHandler } }
      }
    })
    
    # First origin allowed
    result1 = @app.call(**build_env('/data', origin: 'https://app.example.com'))
    assert_equal 'https://app.example.com', result1[:headers]['Access-Control-Allow-Origin']
    
    # Second origin allowed
    result2 = @app.call(**build_env('/data', origin: 'https://staging.example.com'))
    assert_equal 'https://staging.example.com', result2[:headers]['Access-Control-Allow-Origin']
    
    # Disallowed origin
    result3 = @app.call(**build_env('/data', origin: 'https://evil.com'))
    refute result3[:headers].key?('Access-Control-Allow-Origin')
  end

  # Test: Actual request proceeds after CORS check
  def test_actual_request_proceeds
    cors = Aris::Plugins::Cors.build(origins: '*')
    
    Aris.routes({
      "api.example.com": {
        use: [cors],
        "/data": { post: { to: CorsHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', method: 'POST', origin: 'https://app.example.com'))
    
    # Handler executed
    assert_equal 200, result[:status]
    assert_match /Success/, result[:body].first
    
    # CORS headers still set
    assert_equal '*', result[:headers]['Access-Control-Allow-Origin']
  end

  # Test: Different CORS configs per domain
  def test_different_configs_per_domain
    public_cors = Aris::Plugins::Cors.build(origins: '*')
    
    restricted_cors = Aris::Plugins::Cors.build(
      origins: ['https://admin.example.com'],
      credentials: true
    )
    
    Aris.routes({
      "api.example.com": {
        use: [public_cors],
        "/public": { get: { to: CorsHandler } }
      },
      "admin-api.example.com": {
        use: [restricted_cors],
        "/private": { get: { to: CorsHandler } }
      }
    })
    
    # Public API - wildcard
    result1 = @app.call(
      method: 'GET',
      path: '/public',
      domain: 'api.example.com',
      headers: { 'HTTP_ORIGIN' => 'https://anywhere.com' }
    )
    assert_equal '*', result1[:headers]['Access-Control-Allow-Origin']
    
    # Admin API - restricted
    result2 = @app.call(
      method: 'GET',
      path: '/private',
      domain: 'admin-api.example.com',
      headers: { 'HTTP_ORIGIN' => 'https://admin.example.com' }
    )
    assert_equal 'https://admin.example.com', result2[:headers]['Access-Control-Allow-Origin']
    assert_equal 'true', result2[:headers]['Access-Control-Allow-Credentials']
  end
end