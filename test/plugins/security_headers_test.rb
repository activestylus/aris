# test/plugins/security_headers_test.rb
require_relative '../test_helper'

class SecureHandler
  def self.call(request, params)
    "Secure response"
  end
end

class SecurityHeadersTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path)
    {
      method: 'GET',
      path: path,
      domain: 'example.com',
      headers: {},
      body: ''
    }
  end
  
  def test_default_headers_applied
    security = Aris::Plugins::SecurityHeaders.build
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 200, result[:status]
    assert_equal 'SAMEORIGIN', result[:headers]['X-Frame-Options']
    assert_equal 'nosniff', result[:headers]['X-content-type-Options']
    assert_equal '0', result[:headers]['X-XSS-Protection']
    assert_equal 'strict-origin-when-cross-origin', result[:headers]['Referrer-Policy']
  end

  def test_custom_x_frame_options
    security = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'DENY')
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 'DENY', result[:headers]['X-Frame-Options']
  end

  def test_disable_x_frame_options
    security = Aris::Plugins::SecurityHeaders.build(x_frame_options: nil)
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    refute result[:headers].key?('X-Frame-Options')
  end

  def test_hsts_simple
    security = Aris::Plugins::SecurityHeaders.build(hsts: true)
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 'max-age=31536000; includeSubDomains', result[:headers]['Strict-Transport-Security']
  end

  def test_hsts_custom_config
    security = Aris::Plugins::SecurityHeaders.build(
      hsts: {
        max_age: 63072000,
        include_subdomains: true,
        preload: true
      })
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 'max-age=63072000; includeSubDomains; preload', result[:headers]['Strict-Transport-Security']
  end

  def test_content_security_policy
    security = Aris::Plugins::SecurityHeaders.build(csp: "default-src 'self'; script-src 'self' 'unsafe-inline'")
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal "default-src 'self'; script-src 'self' 'unsafe-inline'", result[:headers]['Content-Security-Policy']
  end

  def test_custom_referrer_policy
    security = Aris::Plugins::SecurityHeaders.build(referrer_policy: 'no-referrer')
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 'no-referrer', result[:headers]['Referrer-Policy']
  end

  def test_permissions_policy
    security = Aris::Plugins::SecurityHeaders.build(permissions_policy: 'geolocation=(), microphone=()')
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    assert_equal 'geolocation=(), microphone=()', result[:headers]['Permissions-Policy']
  end

  def test_disable_defaults
    security = Aris::Plugins::SecurityHeaders.build(defaults: false, hsts: true)
    Aris.routes({"example.com": {use: [security],"/data": { get: { to: SecureHandler } }}})
    result = @app.call(**build_env('/data'))
    refute result[:headers].key?('X-Frame-Options')
    refute result[:headers].key?('X-content-type-Options')
    assert result[:headers].key?('Strict-Transport-Security')
  end

  # Test: Multiple configs
  def test_multiple_configs
    security = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'DENY',
      x_content_type_options: 'nosniff',
      hsts: { max_age: 31536000 },
      csp: "default-src 'self'",
      referrer_policy: 'same-origin',
      permissions_policy: 'camera=()')
    Aris.routes({
      "example.com": {
        use: [security],
        "/data": { get: { to: SecureHandler } }
      }
    })
    result = @app.call(**build_env('/data'))
    
    assert_equal 'DENY', result[:headers]['X-Frame-Options']
    assert_equal 'nosniff', result[:headers]['X-content-type-Options']
    assert result[:headers]['Strict-Transport-Security']
    assert result[:headers]['Content-Security-Policy']
    assert_equal 'same-origin', result[:headers]['Referrer-Policy']
    assert_equal 'camera=()', result[:headers]['Permissions-Policy']
  end

  # Test: Headers don't affect response body
  def test_headers_dont_affect_body
    security = Aris::Plugins::SecurityHeaders.build
    
    Aris.routes({
      "example.com": {
        use: [security],
        "/data": { get: { to: SecureHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    
    assert_equal 200, result[:status]
    assert_equal "Secure response", result[:body].first
  end

  # Test: Different security configs per domain
  def test_different_configs_per_domain
    strict_security = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'DENY',
      hsts: { max_age: 63072000, preload: true })
    
    relaxed_security = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'SAMEORIGIN')
    
    Aris.routes({
      "api.example.com": {
        use: [strict_security],
        "/data": { get: { to: SecureHandler } }
      },
      "public.example.com": {
        use: [relaxed_security],
        "/info": { get: { to: SecureHandler } }
      }
    })
    
    result = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'api.example.com',
      headers: {},
      body: ''
    )
    assert_equal 'DENY', result[:headers]['X-Frame-Options']
    assert result[:headers]['Strict-Transport-Security'].include?('preload')
    result = @app.call(
      method: 'GET',
      path: '/info',
      domain: 'public.example.com',
      headers: {},
      body: ''
    )
    assert_equal 'SAMEORIGIN', result[:headers]['X-Frame-Options']
    refute result[:headers].key?('Strict-Transport-Security')
  end
end