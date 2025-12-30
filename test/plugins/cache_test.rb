# test/plugins/cache_test.rb
require_relative '../test_helper'


class CacheHandler
  @@call_count = 0
  
  def self.call(request, params)
    @@call_count += 1
    { message: "Response #{@@call_count}", timestamp: Time.now.to_i }
  end
  
  def self.reset_count
    @@call_count = 0
  end
  
  def self.call_count
    @@call_count
  end
end

class SlowHandler
  def self.call(request, params)
    sleep 0.1
    "Slow response"
  end
end

class CacheTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
    CacheHandler.reset_count
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET', cache_control: nil)
    headers = {}
    headers['HTTP_CACHE_CONTROL'] = cache_control if cache_control
    
    {
      method: method,
      path: path,
      domain: 'example.com',
      headers: headers,
      body: ''
    }
  end
  
  # Test: Caches GET responses
  def test_caches_get_responses
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    # First request - cache miss
    result1 = @app.call(**build_env('/data'))
    assert_equal 200, result1[:status]
    assert_equal 'MISS', result1[:headers]['X-Cache']
    assert_equal 1, CacheHandler.call_count
    
    # Second request - cache hit
    result2 = @app.call(**build_env('/data'))
    assert_equal 200, result2[:status]
    assert_equal 'HIT', result2[:headers]['X-Cache']
    assert_equal 1, CacheHandler.call_count  # Handler not called again
    
    # Responses should be identical
    assert_equal result1[:body], result2[:body]
  end
  
  # Test: Cache expires after TTL
  def test_cache_expires
    cache = Aris::Plugins::Cache.build(ttl: 1)  # 1 second TTL
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    # First request
    result1 = @app.call(**build_env('/data'))
    assert_equal 'MISS', result1[:headers]['X-Cache']
    assert_equal 1, CacheHandler.call_count
    
    # Wait for expiry
    sleep 1.1
    
    # After expiry - should be cache miss
    result2 = @app.call(**build_env('/data'))
    assert_equal 'MISS', result2[:headers]['X-Cache']
    assert_equal 2, CacheHandler.call_count  # Handler called again
  end
  
  # Test: Different paths have different cache keys
  def test_different_paths_different_keys
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data1": { get: { to: CacheHandler } },
        "/data2": { get: { to: CacheHandler } }
      }
    })
    
    result1 = @app.call(**build_env('/data1'))
    result2 = @app.call(**build_env('/data2'))
    
    assert_equal 2, CacheHandler.call_count  # Both paths called handler
    refute_equal result1[:body], result2[:body]
  end
  
  # Test: Query strings affect cache key
  def test_query_string_affects_cache
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    result1 = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'example.com',
      headers: {},
      body: '',
      query: 'page=1'
    )
    
    result2 = @app.call(
      method: 'GET',
      path: '/data',
      domain: 'example.com',
      headers: {},
      body: '',
      query: 'page=2'
    )
    
    assert_equal 2, CacheHandler.call_count  # Different query = different cache key
  end
  
  # Test: Only caches GET requests
  def test_only_caches_get
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { 
          get: { to: CacheHandler },
          post: { to: CacheHandler }
        }
      }
    })
    
    # GET request - cached
    @app.call(**build_env('/data', method: 'GET'))
    @app.call(**build_env('/data', method: 'GET'))
    assert_equal 1, CacheHandler.call_count
    
    # POST request - not cached
    @app.call(**build_env('/data', method: 'POST'))
    @app.call(**build_env('/data', method: 'POST'))
    assert_equal 3, CacheHandler.call_count  # Called twice for POST
  end
  
  # Test: Skip cache with Cache-Control header
  def test_skip_cache_with_header
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    # Normal request - cached
    @app.call(**build_env('/data'))
    assert_equal 1, CacheHandler.call_count
    
    # With no-cache header - bypasses cache
    @app.call(**build_env('/data', cache_control: 'no-cache'))
    assert_equal 2, CacheHandler.call_count
  end
  
  # Test: Skip specific paths
  def test_skip_paths
    cache = Aris::Plugins::Cache.build(
      ttl: 60,
      skip_paths: [/^\/admin/, /^\/health/]
    )
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } },
        "/admin": { get: { to: CacheHandler } },
        "/health": { get: { to: CacheHandler } }
      }
    })
    
    # /data - cached
    @app.call(**build_env('/data'))
    @app.call(**build_env('/data'))
    assert_equal 1, CacheHandler.call_count
    
    # /admin - not cached
    @app.call(**build_env('/admin'))
    @app.call(**build_env('/admin'))
    assert_equal 3, CacheHandler.call_count
    
    # /health - not cached
    @app.call(**build_env('/health'))
    @app.call(**build_env('/health'))
    assert_equal 5, CacheHandler.call_count
  end
  
  # Test: Custom Cache-Control header
  def test_custom_cache_control
    cache = Aris::Plugins::Cache.build(
      ttl: 60,
      cache_control: 'public, max-age=3600'
    )
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 'public, max-age=3600', result[:headers]['Cache-Control']
  end
  
  # Test: Performance improvement
  def test_performance_improvement
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/slow": { get: { to: SlowHandler } }
      }
    })
    
    # First request - slow
    start1 = Time.now
    @app.call(**build_env('/slow'))
    duration1 = Time.now - start1
    
    # Second request - fast (cached)
    start2 = Time.now
    @app.call(**build_env('/slow'))
    duration2 = Time.now - start2
    
    assert duration2 < duration1 / 10  # Cache should be 10x+ faster
  end
  
  # Test: Clear cache
  def test_clear_cache
    cache = Aris::Plugins::Cache.build(ttl: 60)
    
    Aris.routes({
      "example.com": {
        use: [cache],
        "/data": { get: { to: CacheHandler } }
      }
    })
    
    # Cache response
    @app.call(**build_env('/data'))
    assert_equal 1, CacheHandler.call_count
    
    # Hit cache
    @app.call(**build_env('/data'))
    assert_equal 1, CacheHandler.call_count
    
    # Clear cache
    cache.clear!
    
    # Should be cache miss
    @app.call(**build_env('/data'))
    assert_equal 2, CacheHandler.call_count
  end
end