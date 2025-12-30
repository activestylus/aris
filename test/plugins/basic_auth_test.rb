# test/plugins/basic_auth_test.rb
require_relative '../test_helper'

class ProtectedHandler
  def self.call(request, params)
    current_user = request.instance_variable_get(:@current_user)
    "Welcome, #{current_user}!"
  end
end
class BasicAuthTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "admin.example.com"
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
      domain: 'admin.example.com',
      headers: headers,
      body: ''
    }
  end
  def basic_auth_header(username, password)
    encoded = Base64.strict_encode64("#{username}:#{password}")
    "Basic #{encoded}"
  end
  def test_valid_credentials_pass
    auth = Aris::Plugins::BasicAuth.build(username: 'admin', password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('admin', 'secret123')))
    assert_equal 200, result[:status]
    assert_equal "Welcome, admin!", result[:body].first
  end
  def test_invalid_password_returns_401
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('admin', 'wrongpass')))
    assert_equal 401, result[:status]
    assert_equal 'text/plain', result[:headers]['content-type']
    assert_match /WWW-Authenticate/, result[:headers].keys.join(',')
    assert_match /Invalid username or password/, result[:body].first
  end
  def test_invalid_username_returns_401
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('hacker', 'secret123')))
    assert_equal 401, result[:status]
    assert_match /Invalid username or password/, result[:body].first
  end
  def test_missing_auth_header_returns_401
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard'))
    assert_equal 401, result[:status]
    assert result[:headers]['WWW-Authenticate'].include?('Basic realm=')
    assert_match /Missing or invalid Authorization header/, result[:body].first
  end

  # Test: WWW-Authenticate header includes custom realm
  def test_custom_realm_in_header
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123',realm: 'Admin Control Panel')
    Aris.routes({
      "admin.example.com": {
        use: [auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard'))
    assert_equal 401, result[:status]
    assert_match /Basic realm="Admin Control Panel"/, result[:headers]['WWW-Authenticate']
  end

  def test_custom_validator_with_proc
    users = {'alice' => 'password1','bob' => 'password2'}
    auth = Aris::Plugins::BasicAuth.build(validator: ->(username, password) {users[username] == password})
    Aris.routes({
      "admin.example.com": {
        use: [auth], "/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('alice', 'password1')))
    assert_equal 200, result[:status]
    assert_equal "Welcome, alice!", result[:body].first

    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('bob', 'password2')))
    assert_equal 200, result[:status]
    assert_equal "Welcome, bob!", result[:body].first
    
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('alice', 'wrongpass')))
    assert_equal 401, result[:status]
  end

  def test_malformed_auth_header
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],"/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: 'Basic NOTVALIDBASE64!!!'))
    assert_equal 401, result[:status]
    assert_match /Invalid credentials format/, result[:body].first
  end

  def test_wrong_auth_scheme_returns_401
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],"/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: 'Bearer some-token'))
    assert_equal 401, result[:status]
    assert_match /Missing or invalid Authorization header/, result[:body].first
  end

  def test_empty_credentials_fail
    auth = Aris::Plugins::BasicAuth.build(username: 'admin',password: 'secret123')
    Aris.routes({
      "admin.example.com": {
        use: [auth],"/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('', 'secret123')))
    assert_equal 401, result[:status]

    result = @app.call(**build_env('/dashboard', auth_header: basic_auth_header('admin', '')))
    assert_equal 401, result[:status]
  end

  def test_multiple_auth_instances
    admin_auth = Aris::Plugins::BasicAuth.build(username: 'admin', password: 'admin123',realm: 'Admin Area')
    api_auth = Aris::Plugins::BasicAuth.build(username: 'api', password: 'api456',realm: 'API Access')
    Aris.routes({
      "admin.example.com": {
        use: [admin_auth],
        "/dashboard": { get: { to: ProtectedHandler } }
      },
      "api.example.com": {
        use: [api_auth],
        "/data": { get: { to: ProtectedHandler } }
      }
    })
    result = @app.call(
      method: 'GET',
      path: '/dashboard',
      domain: 'admin.example.com',
      headers: { 'HTTP_AUTHORIZATION' => basic_auth_header('admin', 'admin123') }
    )
    assert_equal 200, result[:status]
    result = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'api.example.com',
      headers: { 'HTTP_AUTHORIZATION' => basic_auth_header('api', 'api456') }
    )
    assert_equal 200, result[:status]
    result = @app.call(
      method: 'GET',
      path: '/dashboard',
      domain: 'admin.example.com',
      headers: { 'HTTP_AUTHORIZATION' => basic_auth_header('api', 'api456') }
    )
    assert_equal 401, result[:status]
  end

  def test_validator_receives_correct_args
    captured_username = nil
    captured_password = nil
    auth = Aris::Plugins::BasicAuth.build(
      validator: ->(u, p) {
        captured_username = u
        captured_password = p
        true  # Always pass for this test
      }
    )
    Aris.routes({
      "admin.example.com": {
        use: [auth],"/dashboard": { get: { to: ProtectedHandler } }
      }
    })
    @app.call(**build_env('/dashboard', auth_header: basic_auth_header('testuser', 'testpass')))
    assert_equal 'testuser', captured_username
    assert_equal 'testpass', captured_password
  end

  def test_missing_config_raises_error
    error = assert_raises(ArgumentError) do
      Aris::Plugins::BasicAuth.build  # No config at all
    end
    assert_match /requires either :validator or both :username and :password/, error.message
  end

  
  def test_incomplete_credentials_raises_error
    error = assert_raises(ArgumentError) do
      Aris::Plugins::BasicAuth.build(username: 'admin')  # Missing password
    end
    assert_match /requires either :validator or both :username and :password/, error.message
  end
end