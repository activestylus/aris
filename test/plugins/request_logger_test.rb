# test/plugins/request_logger_test.rb
require_relative '../test_helper'
require 'stringio'

class LoggedHandler
  def self.call(request, params)
    "Response"
  end
end

class RequestLoggerTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET')
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'example.com',
      headers: {},
      body: ''
    }
  end
  
  def test_text_format_logging
    logger = Aris::Plugins::RequestLogger.build(format: :text,logger: @logger)
    Aris.routes({
      "example.com": {use: [logger],"/data": { get: { to: LoggedHandler } }}
    })
    @app.call(**build_env('/data'))
    log_content = @log_output.string
    assert_match /GET \/data/, log_content
  end

  def test_json_format_logging
    logger = Aris::Plugins::RequestLogger.build(format: :json,logger: @logger)
    Aris.routes({"example.com": {use: [logger],"/data": { get: { to: LoggedHandler } }}})
    @app.call(**build_env('/data'))
    log_content = @log_output.string
    json_match = log_content.match(/({.+})/)
    parsed = JSON.parse(json_match[1])
    assert_equal 'GET', parsed['method']
    assert_equal '/data', parsed['path']
    assert_equal 'example.com', parsed['host']
    assert parsed['timestamp']
  end

  def test_exclude_paths
    logger = Aris::Plugins::RequestLogger.build(format: :text, exclude: ['/health', '/metrics'],logger: @logger)
    Aris.routes({
      "example.com": {use: [logger],"/data": { get: { to: LoggedHandler } },"/health": { get: { to: LoggedHandler } }
      }
    })
    @app.call(**build_env('/data'))
    assert_match /\/data/, @log_output.string
    @log_output.truncate(0)
    @log_output.rewind
    @app.call(**build_env('/health'))
    assert_empty @log_output.string
  end

  def test_different_http_methods
    logger = Aris::Plugins::RequestLogger.build(format: :text,logger: @logger)
    Aris.routes({
      "example.com": {use: [logger],
        "/users": {
          get: { to: LoggedHandler },
          post: { to: LoggedHandler },
          delete: { to: LoggedHandler }
        }
      }
    })
    @app.call(**build_env('/users', method: 'GET'))
    assert_match /GET \/users/, @log_output.string
    @log_output.truncate(0)
    @log_output.rewind
    @app.call(**build_env('/users', method: 'POST'))
    assert_match /POST \/users/, @log_output.string
    @log_output.truncate(0)
    @log_output.rewind
    @app.call(**build_env('/users', method: 'DELETE'))
    assert_match /DELETE \/users/, @log_output.string
  end

  def test_multiple_excluded_paths
    logger = Aris::Plugins::RequestLogger.build(
      format: :text,
      exclude: ['/health', '/metrics', '/ping'],
      logger: @logger
    )
    
    Aris.routes({
      "example.com": {
        use: [logger],
        "/data": { get: { to: LoggedHandler } },
        "/health": { get: { to: LoggedHandler } },
        "/metrics": { get: { to: LoggedHandler } },
        "/ping": { get: { to: LoggedHandler } }
      }
    })
    
    # Test that /data IS logged
    @app.call(**build_env('/data'))  # ← Changed from /users
    assert_match /\/data/, @log_output.string
    
    # Clear log
    @log_output.truncate(0)
    @log_output.rewind
    
    # Test that excluded paths are NOT logged
    @app.call(**build_env('/health'))
    @app.call(**build_env('/metrics'))
    @app.call(**build_env('/ping'))
    
    assert_empty @log_output.string
  end

  def test_default_format_is_text
    logger = Aris::Plugins::RequestLogger.build(logger: @logger)
    Aris.routes({
      "example.com": {use: [logger],"/data": { get: { to: LoggedHandler } }}
    })
    @app.call(**build_env('/data'))
    log_content = @log_output.string
    assert_match /GET \/data/, log_content
    refute_match /{.*}/, log_content
  end

  def test_logs_dont_affect_response
    logger = Aris::Plugins::RequestLogger.build(logger: @logger)
    Aris.routes({
      "example.com": {use: [logger],"/data": { get: { to: LoggedHandler } }}
    })
    result = @app.call(**build_env('/data'))
    assert_equal 200, result[:status]
    assert_equal "Response", result[:body].first
  end

  def test_different_loggers_per_domain
    log1 = StringIO.new
    log2 = StringIO.new
    logger1 = Aris::Plugins::RequestLogger.build(logger: Logger.new(log1))
    logger2 = Aris::Plugins::RequestLogger.build(logger: Logger.new(log2))
    
    Aris.routes({
      "api.example.com": {
        use: [logger1],
        "/data": { get: { to: LoggedHandler } }
      },
      "admin.example.com": {
        use: [logger2],
        "/admin": { get: { to: LoggedHandler } }
      }
    })
    
    # API request
    @app.call(
      method: 'GET',
      path: '/data',
      domain: 'api.example.com',
      headers: {},
      body: ''
    )
    
    # Admin request
    @app.call(
      method: 'GET',
      path: '/admin',
      domain: 'admin.example.com',
      headers: {},
      body: ''
    )
    
    # Check separate logs
    assert_match /\/data/, log1.string
    refute_match /\/admin/, log1.string
    
    assert_match /\/admin/, log2.string
    refute_match /\/data/, log2.string
  end
end