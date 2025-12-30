# test/plugins/api_key_auth_test.rb
require_relative '../test_helper'

class ApiKeyProtectedHandler
  def self.call(request, params)
    key = request.instance_variable_get(:@api_key)
    { status: 'success', key: key }.to_json
  end
end

class ApiKeyAuthTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "api.example.com"
    # ... define routes ...
    @app = Aris::Adapters::Mock::Adapter.new
  end
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  def build_env(path, method: 'GET', api_key: nil, auth: nil, body: '', header: nil, **extra_headers)
    headers = extra_headers.dup
    
    # If custom header specified, use it; otherwise use default
    if api_key
      if header
        # Convert "X-Custom-Key" → "HTTP_X_CUSTOM_KEY"
        rack_header = "HTTP_#{header.upcase.gsub('-', '_')}"
        headers[rack_header] = api_key
      else
        headers['HTTP_X_API_KEY'] = api_key  # Default
      end
    end
    
    headers['HTTP_AUTHORIZATION'] = auth if auth
    
    {
      method: method,
      path: path,
      domain: 'api.example.com',
      headers: headers,
      body: body
    }
  end
  def assert_response(result, status:, content_type: nil)
    assert_equal status, result[:status], "Expected status #{status}, got #{result[:status]}"
    assert_equal content_type, result[:headers]['content-type'] if content_type
    result
  end

  def test_valid_key_passes
    auth = Aris::Plugins::ApiKeyAuth.build(key: 'secret-key-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'secret-key-123')) 
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 'success', response['status']
    assert_equal 'secret-key-123', response['key']
  end

  def test_invalid_key_returns_401
    auth = Aris::Plugins::ApiKeyAuth.build(key: 'secret-key-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'wrong-key'))
    assert_response(result, status: 401, content_type: 'application/json')
    response = JSON.parse(result[:body].first)
    assert_equal 'Unauthorized', response['error']
    assert_match /Invalid API key/, response['message']
  end

  def test_missing_key_returns_401
    auth = Aris::Plugins::ApiKeyAuth.build(key: 'secret-key-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'wrong-key'))
    assert_equal 401, result[:status]
    response = JSON.parse(result[:body].first)
    assert_match /Invalid API key/, response['message']
  end

  def test_empty_key_returns_401
    auth = Aris::Plugins::ApiKeyAuth.build(key: 'secret-key-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'wrong-key'))
    assert_equal 401, result[:status]
    response = JSON.parse(result[:body].first)
    assert_match /Invalid API key/, response['message']
  end

  def test_multiple_valid_keys
    auth = Aris::Plugins::ApiKeyAuth.build(
      keys: ['key-1', 'key-2', 'key-3']
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    ['key-1', 'key-2', 'key-3'].each do |key|
      result = @app.call(**build_env('/data', api_key: key))
      assert_equal 200, result[:status]
    end
    result = @app.call(**build_env('/data', api_key: 'wrong-key'))
    assert_equal 401, result[:status]
  end

  def test_custom_validator
    valid_keys = { 'user-1-key' => 'user-1', 'user-2-key' => 'user-2' }
    auth = Aris::Plugins::ApiKeyAuth.build(
      validator: ->(key) { valid_keys.key?(key) }
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'user-1-key'))
    assert_equal 200, result[:status]
    result = @app.call(**build_env('/data', api_key: 'user-2-key'))
    assert_equal 200, result[:status]
    result = @app.call(**build_env('/data', api_key: 'invalid-key'))
    assert_equal 401, result[:status]
  end

  def test_custom_header_name
    auth = Aris::Plugins::ApiKeyAuth.build(
      key: 'secret-key',
      header: 'X-Custom-Key'
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'secret-key', header: 'X-Custom-Key'))
    assert_equal 200, result[:status]
  end



  def test_custom_realm
    auth = Aris::Plugins::ApiKeyAuth.build(
      key: 'secret-key',
      realm: 'Partner API'
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })


    result = @app.call(**build_env('/data', api_key: 'secret-key-123')) 
    assert_equal 401, result[:status]
    assert_match /ApiKey realm="Partner API"/, result[:headers]['WWW-Authenticate']
  end

  def test_long_keys
    long_key = 'a' * 500
    auth = Aris::Plugins::ApiKeyAuth.build(key: long_key)
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: long_key))
    assert_equal 200, result[:status]
  end

  def test_special_characters_in_keys
    special_key = 'key-with_special.chars+symbols='
    auth = Aris::Plugins::ApiKeyAuth.build(key: special_key)
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: special_key))
    assert_equal 200, result[:status]
  end

  def test_multiple_instances
    public_auth = Aris::Plugins::ApiKeyAuth.build(key: 'public-key')
    admin_auth = Aris::Plugins::ApiKeyAuth.build(key: 'admin-key')
    Aris.routes({
      "api.example.com": {
        use: [public_auth],
        "/public": { get: { to: ApiKeyProtectedHandler } }
      },
      "admin-api.example.com": {
        use: [admin_auth],
        "/admin": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    
    # Test public domain with public key - should pass
    result = @app.call(
      method: 'GET',
      path: '/public',
      domain: 'api.example.com',
      headers: { 'HTTP_X_API_KEY' => 'public-key' }
    )
    assert_equal 200, result[:status]
    
    # Test admin domain with admin key - should pass
    result = @app.call(
      method: 'GET',
      path: '/admin',
      domain: 'admin-api.example.com',
      headers: { 'HTTP_X_API_KEY' => 'admin-key' }
    )
    assert_equal 200, result[:status]
    
    # Test admin domain with wrong key - should fail
    result = @app.call(
      method: 'GET',
      path: '/admin',
      domain: 'admin-api.example.com',
      headers: { 'HTTP_X_API_KEY' => 'public-key' }
    )
    assert_equal 401, result[:status]
  end

  def test_missing_config_raises_error
    error = assert_raises(ArgumentError) do
      Aris::Plugins::ApiKeyAuth.build
    end
    assert_match /requires :validator, :key, or :keys/, error.message
  end

  def test_validator_receives_correct_key
    captured_key = nil
    auth = Aris::Plugins::ApiKeyAuth.build(
      validator: ->(key) {
        captured_key = key
        true
      }
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],
        "/data": { get: { to: ApiKeyProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', api_key: 'test-key-456'))
    assert_equal 'test-key-456', captured_key
  end
end