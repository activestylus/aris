require_relative '../test_helper'
class BearerProtectedHandler
  def self.call(request, params)
    # Access the token that was validated by the plugin
    token = request.instance_variable_get(:@bearer_token)
    
    {
      status: 'success',
      token: token
    }
  end
end
class BearerAuthTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "api.example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, auth_header: nil)
    headers = {}
    headers['HTTP_AUTHORIZATION'] = auth_header if auth_header
    
    {
      method: 'GET',
      path: path,
      domain: 'api.example.com',
      headers: headers,
      body: ''
    }
  end
  
  def bearer_header(token)
    "Bearer #{token}"
  end
  
  # Test: Valid token passes through
  def test_valid_token_passes
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],"/data": { get: { to: BearerProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', auth_header: bearer_header('secret-token-123')))
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 'success', response['status']
    assert_equal 'secret-token-123', response['token']
  end

  def test_invalid_token_returns_401
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {
        use: [auth],"/data": { get: { to: BearerProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', auth_header: bearer_header('wrong-token')))
    assert_equal 401, result[:status]
    assert_equal 'application/json', result[:headers]['content-type']
    response = JSON.parse(result[:body].first)
    assert_equal 'Unauthorized', response['error']
    assert_match /Invalid or expired token/, response['message']
  end

  def test_missing_auth_header_returns_401
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {use: [auth], "/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data'))
    assert_equal 401, result[:status]
    assert result[:headers]['WWW-Authenticate'].include?('Bearer realm=')
    response = JSON.parse(result[:body].first)
    assert_match /Missing or invalid Authorization header/, response['message']
  end

  def test_custom_realm_in_header
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123',realm: 'My API v2')
    Aris.routes({
      "api.example.com": {
        use: [auth], "/data": { get: { to: BearerProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data'))
    assert_equal 401, result[:status]
    assert_match /Bearer realm="My API v2"/, result[:headers]['WWW-Authenticate']
  end

  def test_custom_validator_with_proc
    valid_tokens = ['token-abc', 'token-xyz', 'token-123']
    auth = Aris::Plugins::BearerAuth.build(
      validator: ->(token) { valid_tokens.include?(token) }
    )
    Aris.routes({
      "api.example.com": {
        use: [auth],"/data": { get: { to: BearerProtectedHandler } }
      }
    })
    valid_tokens.each do |token|
      result = @app.call(**build_env('/data', auth_header: bearer_header(token)))
      assert_equal 200, result[:status]
      response = JSON.parse(result[:body].first)
      assert_equal token, response['token']
    end
    result = @app.call(**build_env('/data', auth_header: bearer_header('invalid-token')))
    assert_equal 401, result[:status]
  end

  def test_empty_token_returns_401
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data', auth_header: 'Bearer '))
    assert_equal 401, result[:status]
    response = JSON.parse(result[:body].first)
    assert_match /Invalid token format/, response['message']
  end

  def test_token_whitespace_trimmed
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {
        use: [auth], 
        "/data": { get: { to: BearerProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/data', auth_header: bearer_header('  secret-token-123  ')))
    assert_equal 200, result[:status]
  end

  def test_wrong_auth_scheme_returns_401
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data', auth_header: 'Basic dXNlcjpwYXNz'))
    assert_equal 401, result[:status]
    response = JSON.parse(result[:body].first)
    assert_match /Missing or invalid Authorization header/, response['message']
  end

  def test_malformed_header_returns_401
    auth = Aris::Plugins::BearerAuth.build(token: 'secret-token-123')
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data', auth_header: 'NotEvenClose'))
    assert_equal 401, result[:status]
  end

  def test_multiple_auth_instances
    admin_auth = Aris::Plugins::BearerAuth.build(
      token: 'admin-token-xyz',
      realm: 'Admin API'
    )
    public_auth = Aris::Plugins::BearerAuth.build(
      token: 'public-token-abc',
      realm: 'Public API'
    )
    Aris.routes({
      "admin.api.com": {
        use: [admin_auth],
        "/admin": { get: { to: BearerProtectedHandler } }
      },
      "public.api.com": {
        use: [public_auth],
        "/data": { get: { to: BearerProtectedHandler } }
      }
    })
    result = @app.call(
      method: 'GET',
      path: '/admin',
      domain: 'admin.api.com',
      headers: { 'HTTP_AUTHORIZATION' => bearer_header('admin-token-xyz') }
    )
    assert_equal 200, result[:status]
    result = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'public.api.com',
      headers: { 'HTTP_AUTHORIZATION' => bearer_header('public-token-abc') }
    )
    assert_equal 200, result[:status]
    result = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'public.api.com',
      headers: { 'HTTP_AUTHORIZATION' => bearer_header('admin-token-xyz') }
    )
    assert_equal 401, result[:status]
  end

  def test_validator_receives_correct_token
    captured_token = nil
    auth = Aris::Plugins::BearerAuth.build(
      validator: ->(token) {
        captured_token = token
        true
      }
    )
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    @app.call(**build_env('/data', auth_header: bearer_header('test-token-456')))
    assert_equal 'test-token-456', captured_token
  end

  def test_long_tokens_handled
    long_token = 'a' * 1000
    auth = Aris::Plugins::BearerAuth.build(token: long_token)
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data', auth_header: bearer_header(long_token)))
    assert_equal 200, result[:status]
  end

  def test_special_characters_in_tokens
    special_token = 'token-with_special.chars+and/symbols='
    auth = Aris::Plugins::BearerAuth.build(token: special_token)
    Aris.routes({
      "api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}
    })
    result = @app.call(**build_env('/data', auth_header: bearer_header(special_token)))
    assert_equal 200, result[:status]
  end

  def test_missing_config_raises_error
    error = assert_raises(ArgumentError) do
      Aris::Plugins::BearerAuth.build
    end
    assert_match /requires either :validator or :token/, error.message
  end

  def test_validator_falsy_values
    auth = Aris::Plugins::BearerAuth.build( validator: ->(token) { nil } )
    Aris.routes({"api.example.com": {use: [auth],"/data": { get: { to: BearerProtectedHandler } }}})
    result = @app.call(**build_env('/data', auth_header: bearer_header('any-token')))
    assert_equal 401, result[:status]
  end
end