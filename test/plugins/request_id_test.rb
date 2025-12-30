# test/plugins/request_id_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/plugins/request_id'

class RequestIdHandler
  def self.call(request, params)
    request_id = request.instance_variable_get(:@request_id)
    { request_id: request_id }
  end
end

class RequestIdTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, request_id: nil)
    headers = {}
    headers['HTTP_X_REQUEST_ID'] = request_id if request_id
    
    {
      method: 'GET',
      path: path,
      domain: 'example.com',
      headers: headers,
      body: ''
    }
  end
  
  # Test: Generates request ID if not provided
  def test_generates_request_id
    request_id = Aris::Plugins::RequestId.build
    
    Aris.routes({
      "example.com": {
        use: [request_id],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 200, result[:status]
    assert result[:headers]['X-Request-ID']
    
    # Should be a UUID format
    assert_match /^[a-f0-9\-]{36}$/, result[:headers]['X-Request-ID']
    
    # Handler should have access to it
    response = JSON.parse(result[:body].first)
    assert_equal result[:headers]['X-Request-ID'], response['request_id']
  end
  
  # Test: Preserves existing request ID
  def test_preserves_existing_request_id
    request_id = Aris::Plugins::RequestId.build
    
    Aris.routes({
      "example.com": {
        use: [request_id],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    existing_id = 'custom-request-id-12345'
    result = @app.call(**build_env('/data', request_id: existing_id))
    
    assert_equal 200, result[:status]
    assert_equal existing_id, result[:headers]['X-Request-ID']
    
    response = JSON.parse(result[:body].first)
    assert_equal existing_id, response['request_id']
  end
  
  # Test: Custom header name
  def test_custom_header_name
    request_id = Aris::Plugins::RequestId.build(header_name: 'X-Trace-ID')
    
    Aris.routes({
      "example.com": {
        use: [request_id],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 200, result[:status]
    assert result[:headers]['X-Trace-ID']
    refute result[:headers]['X-Request-ID']
  end
  
  # Test: Custom generator
  def test_custom_generator
    counter = 0
    request_id = Aris::Plugins::RequestId.build(
      generator: -> { "REQ-#{counter += 1}" }
    )
    
    Aris.routes({
      "example.com": {
        use: [request_id],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    result1 = @app.call(**build_env('/data'))
    assert_equal 'REQ-1', result1[:headers]['X-Request-ID']
    
    result2 = @app.call(**build_env('/data'))
    assert_equal 'REQ-2', result2[:headers]['X-Request-ID']
  end
  
  # Test: Different requests get different IDs
  def test_different_requests_different_ids
    request_id = Aris::Plugins::RequestId.build
    
    Aris.routes({
      "example.com": {
        use: [request_id],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    result1 = @app.call(**build_env('/data'))
    result2 = @app.call(**build_env('/data'))
    
    refute_equal result1[:headers]['X-Request-ID'], result2[:headers]['X-Request-ID']
  end
  
  # Test: Works with logging plugin
  def test_works_with_logger
    log_output = StringIO.new
    logger = Logger.new(log_output)
    
    request_id = Aris::Plugins::RequestId.build
    log_plugin = Aris::Plugins::RequestLogger.build(
      format: :text,
      logger: logger
    )
    
    Aris.routes({
      "example.com": {
        use: [request_id, log_plugin],
        "/data": { get: { to: RequestIdHandler } }
      }
    })
    
    result = @app.call(**build_env('/data'))
    
    assert_equal 200, result[:status]
    assert result[:headers]['X-Request-ID']
    
    # Log should contain request
    log_content = log_output.string
    assert_match /GET \/data/, log_content
  end
end