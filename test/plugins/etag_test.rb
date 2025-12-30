# test/plugins/etag_test.rb
require_relative '../test_helper'


class ETagHandler
  def self.call(request, params)
    "Hello, World!"
  end
end

class DynamicHandler
  def self.call(request, params)
    "Data: #{Time.now.to_i}"
  end
end

class JsonETagHandler
  def self.call(request, params)
    { message: "Hello", timestamp: 1234567890 }
  end
end

class ETagTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET', if_none_match: nil)
    headers = {}
    headers['HTTP_IF_NONE_MATCH'] = if_none_match if if_none_match
    
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'example.com',
      headers: headers,
      body: ''
    }
  end
  def test_debug_etag_matching
	  etag = Aris::Plugins::ETag.build
	  
	  Aris.routes({
	    "example.com": {
	      use: [etag],
	      "/data": { get: { to: ETagHandler } }
	    }
	  })
	  result1 = @app.call(**build_env('/data'))
	  etag_value = result1[:headers]['ETag']
	  result2 = @app.call(**build_env('/data', if_none_match: etag_value))
	end
  # Test: Generates ETag for GET request
  def test_generates_etag_for_get
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 200, result[:status]
    assert result[:headers]['ETag']
    assert_match /^"[a-f0-9]{32}"$/, result[:headers]['ETag']  # Strong ETag format
    assert result[:headers]['Cache-Control']
  end
  
  # Test: Returns 304 when ETag matches
  def test_returns_304_when_etag_matches
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    # First request - get the ETag
    result1 = @app.call(**build_env('/data'))
    etag_value = result1[:headers]['ETag']
    
    # Second request - send If-None-Match with same ETag
    result2 = @app.call(**build_env('/data', if_none_match: etag_value))
    
    assert_equal 304, result2[:status]
    assert_empty result2[:body]
    assert_equal etag_value, result2[:headers]['ETag']
  end
  
  # Test: Returns 200 when ETag doesn't match
  def test_returns_200_when_etag_different
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    # Send request with wrong ETag
    result = @app.call(**build_env('/data', if_none_match: '"wrongetag123"'))
    
    assert_equal 200, result[:status]
    refute_empty result[:body]
  end
  
  # Test: Custom cache control
  def test_custom_cache_control
    etag = Aris::Plugins::ETag.build(cache_control: 'public, max-age=3600')
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 'public, max-age=3600', result[:headers]['Cache-Control']
  end
  
  # Test: Weak ETag
  def test_weak_etag
    etag = Aris::Plugins::ETag.build(strong: false)
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_match /^W\/"[a-f0-9]{32}"$/, result[:headers]['ETag']  # Weak ETag format
  end
  
  # Test: Works with JSON responses
  def test_works_with_json
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/json": { get: { to: JsonETagHandler } }
      }
    })
    
    result = @app.call(**build_env('/json'))
    
    assert_equal 200, result[:status]
    assert result[:headers]['ETag']
  end
  
  # Test: Only applies to GET requests
  def test_only_get_requests
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { post: { to: ETagHandler } }
      }
    })
    
    result = @app.call(**build_env('/data', method: 'POST'))
    
    assert_equal 200, result[:status]
    refute result[:headers]['ETag']  # No ETag for POST
  end
  
  # Test: Multiple ETags in If-None-Match
  def test_multiple_etags_in_if_none_match
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    # First request - get the ETag
    result1 = @app.call(**build_env('/data'))
    etag_value = result1[:headers]['ETag']
    
    # Second request - send multiple ETags
    multiple_etags = %("old123", #{etag_value}, "other456")
    result2 = @app.call(**build_env('/data', if_none_match: multiple_etags))
    
    assert_equal 304, result2[:status]
  end
  
  # Test: Same content produces same ETag
  def test_same_content_same_etag
    etag = Aris::Plugins::ETag.build
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/data": { get: { to: ETagHandler } }
      }
    })
    
    result1 = @app.call(**build_env('/data'))
    result2 = @app.call(**build_env('/data'))
    
    assert_equal result1[:headers]['ETag'], result2[:headers]['ETag']
  end
  
  # Test: Does not override existing ETag
  def test_does_not_override_existing_etag
    etag = Aris::Plugins::ETag.build
    
    custom_handler = Class.new do
      def self.call(request, params)
        # Handler that sets its own ETag
        response = Aris::Adapters::Mock::Response.new
        response.body = ["Custom"]
        response.headers['ETag'] = '"custom-etag"'
        response
      end
    end
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/custom": { get: { to: custom_handler } }
      }
    })
    
    result = @app.call(**build_env('/custom'))
    
    assert_equal '"custom-etag"', result[:headers]['ETag']
  end
  
  # Test: Does not set Cache-Control if already present
  def test_does_not_override_cache_control
    etag = Aris::Plugins::ETag.build
    
    custom_handler = Class.new do
      def self.call(request, params)
        response = Aris::Adapters::Mock::Response.new
        response.body = ["Data"]
        response.headers['Cache-Control'] = 'no-cache'
        response
      end
    end
    
    Aris.routes({
      "example.com": {
        use: [etag],
        "/nocache": { get: { to: custom_handler } }
      }
    })
    
    result = @app.call(**build_env('/nocache'))
    
    assert_equal 'no-cache', result[:headers]['Cache-Control']
  end
end