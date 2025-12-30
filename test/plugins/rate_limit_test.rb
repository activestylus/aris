# test/plugins/rate_limiter_test.rb
require_relative '../test_helper'

class RateLimitedHandler
  def self.call(request, params)
    "Success"
  end
end

class RateLimiterTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "api.example.com"
    
    Aris.routes({
      "api.example.com": {
        use: [:rate_limit],
        "/data": { get: { to: RateLimitedHandler } }
      }
    })
    
    @app = Aris::Adapters::Mock::Adapter.new
    
    # Clear rate limiter state before each test
    Aris::Plugins::RateLimiter.reset!
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
    Aris::Plugins::RateLimiter.reset!
  end
  
  def build_env(path, api_key: nil)
    headers = {}
    headers['HTTP_X_API_KEY'] = api_key if api_key
    
    {
      method: 'GET',
      path: path,
      domain: 'api.example.com',
      headers: headers,
      body: ''
    }
  end
  
  def test_requests_under_limit_pass
    10.times do
      result = @app.call(**build_env('/data', api_key: 'test-key'))
      assert_equal 200, result[:status]
      assert_equal "Success", result[:body].first
    end
  end

  def test_request_at_limit_boundary_passes
    100.times do |i|
      result = @app.call(**build_env('/data', api_key: 'boundary-key'))
      assert_equal 200, result[:status], "Request #{i + 1} should succeed"
    end
  end

  def test_request_over_limit_returns_429
    env = build_env('/data', api_key: 'over-limit-key')
    100.times { @app.call(**build_env('/data', api_key: 'over-limit-key')) }
    result = @app.call(**build_env('/data', api_key: 'over-limit-key'))
    assert_equal 429, result[:status]
    assert_equal 'text/plain', result[:headers]['content-type']
    assert_equal '60', result[:headers]['Retry-After']
    assert_match /Rate limit exceeded/, result[:body].first
  end

  def test_multiple_requests_over_limit
    100.times { @app.call(**build_env('/data', api_key: 'spam-key')) }
    10.times do
      result = @app.call(**build_env('/data', api_key: 'spam-key'))
      assert_equal 429, result[:status]
      assert_match /Rate limit exceeded/, result[:body].first
    end
  end

  def test_different_keys_have_separate_limits
    env_key1 = build_env('/data', api_key: 'key-1')
    env_key2 = build_env('/data', api_key: 'key-2')
    100.times { @app.call(**build_env('/data', api_key: 'key-1')) }
    result = @app.call(**build_env('/data', api_key: 'key-1'))
    assert_equal 429, result[:status]
    result = @app.call(**build_env('/data', api_key: 'key-2'))
    assert_equal 200, result[:status]
    assert_equal "Success", result[:body].first
  end

  def test_no_api_key_uses_host
    100.times { @app.call(**build_env('/data')) }
    result = @app.call(**build_env('/data'))
    assert_equal 429, result[:status]
  end

  def test_window_resets_after_expiry
    100.times { @app.call(**build_env('/data', api_key: 'reset-key')) }
    result = @app.call(**build_env('/data', api_key: 'reset-key'))
    assert_equal 429, result[:status]
    Aris::Plugins::RateLimiter.reset!
    result = @app.call(**build_env('/data', api_key: 'reset-key'))
    assert_equal 200, result[:status]
    assert_equal "Success", result[:body].first
  end

  def test_concurrent_requests_counted_correctly
    50.times { @app.call(**build_env('/data', api_key: 'concurrent-key')) }
    threads = 50.times.map do
      Thread.new { @app.call(**build_env('/data', api_key: 'concurrent-key')) }
    end
    threads.each(&:join)
    result = @app.call(**build_env('/data', api_key: 'concurrent-key'))
    assert_equal 429, result[:status]
  end

  def test_rate_limiter_preserves_handler_response
    result = @app.call(**build_env('/data', api_key: 'preserve-key'))
    assert_equal 200, result[:status]
    assert_equal "Success", result[:body].first
    refute result[:headers].key?('Retry-After')
  end

  def test_empty_api_key_uses_host
    100.times { @app.call(**build_env('/data', api_key: '')) }
    result = @app.call(**build_env('/data', api_key: ''))
    assert_equal 429, result[:status]
  end

  def test_long_api_keys_handled
    long_key = 'x' * 1000
    result = @app.call(**build_env('/data', api_key: long_key))
    assert_equal 200, result[:status]
    assert_equal "Success", result[:body].first
  end
end