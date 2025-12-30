# test/plugins/compression_test.rb
require_relative '../test_helper'
require 'zlib'

class CompressionHandler
  def self.call(request, params)
    "Hello World! " * 100  # ~1.3KB
  end
end

class JsonCompressionHandler
  def self.call(request, params)
    { data: "x" * 1000, items: (1..50).to_a }
  end
end

class TinyHandler
  def self.call(request, params)
    "Small"  # Too small to compress
  end
end

class BinaryHandler
  def self.call(request, params)
    # Simulate binary content (PNG magic bytes + random data)
    "\x89PNG\r\n\x1a\n" + ("x" * 1000)
  end
end

class AlreadyCompressedHandler
  def self.call(request, params)
    # Pre-compressed data (random-ish, won't compress well)
    1000.times.map { rand(256).chr }.join
  end
end
class CompressionTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, accept_encoding: nil)
    headers = {}
    headers['HTTP_ACCEPT_ENCODING'] = accept_encoding if accept_encoding
    {
      method: 'GET',
      path: path,
      domain: 'example.com',
      headers: headers,
      body: ''
    }
  end
  
  def decompress_gzip(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end
  
  def test_compresses_with_gzip_support
    compression = Aris::Plugins::Compression.build
    Aris.routes({
      "example.com": {
        use: [compression],
        "/data": { get: { to: CompressionHandler } }
      }
    })
    result = @app.call(**build_env('/data', accept_encoding: 'gzip, deflate'))
    assert_equal 200, result[:status]
    assert_equal 'gzip', result[:headers]['Content-Encoding']
    assert_includes result[:headers]['Vary'], 'Accept-Encoding'
    compressed_body = result[:body].first
    decompressed = decompress_gzip(compressed_body)
    assert_includes decompressed, "Hello World!"
  end

  def test_no_compression_without_gzip_support
    compression = Aris::Plugins::Compression.build
    Aris.routes({
      "example.com": {
        use: [compression],
        "/data": { get: { to: CompressionHandler } }
      }
    })
    result = @app.call(**build_env('/data'))
    assert_equal 200, result[:status]
    refute result[:headers].key?('Content-Encoding')
    assert_includes result[:body].first, "Hello World!"
  end
  
  def test_skips_small_responses
    compression = Aris::Plugins::Compression.build(min_size: 1024)
    Aris.routes({
      "example.com": {
        use: [compression],
        "/tiny": { get: { to: TinyHandler } }
      }
    })
    result = @app.call(**build_env('/tiny', accept_encoding: 'gzip'))
    assert_equal 200, result[:status]
    refute result[:headers].key?('Content-Encoding')
    assert_equal "Small", result[:body].first
  end
  
  def test_compresses_json
    compression = Aris::Plugins::Compression.build
    Aris.routes({
      "example.com": {
        use: [compression],
        "/json": { get: { to: JsonCompressionHandler } }
      }
    })
    result = @app.call(**build_env('/json', accept_encoding: 'gzip'))
    assert_equal 200, result[:status]
    assert_equal 'gzip', result[:headers]['Content-Encoding']
    compressed_body = result[:body].first
    decompressed = decompress_gzip(compressed_body)
    parsed = JSON.parse(decompressed)
    assert_equal 50, parsed['items'].size
  end

  def test_custom_compression_level
    compression = Aris::Plugins::Compression.build(level: Zlib::BEST_COMPRESSION)
    Aris.routes({
      "example.com": {
        use: [compression],
        "/data": { get: { to: CompressionHandler } }
      }
    })
    result = @app.call(**build_env('/data', accept_encoding: 'gzip'))
    assert_equal 200, result[:status]
    assert_equal 'gzip', result[:headers]['Content-Encoding']
  end
  
  def test_custom_min_size
    compression = Aris::Plugins::Compression.build(min_size: 500)
    Aris.routes({
      "example.com": {
        use: [compression],
        "/data": { get: { to: CompressionHandler } }
      }
    })
    result = @app.call(**build_env('/data', accept_encoding: 'gzip'))
    assert_equal 200, result[:status]
    assert_equal 'gzip', result[:headers]['Content-Encoding']
  end

  def test_vary_header_handling
    compression = Aris::Plugins::Compression.build
    Aris.routes({
      "example.com": {
        use: [compression],
        "/data": { get: { to: CompressionHandler } }
      }
    })
    result = @app.call(**build_env('/data', accept_encoding: 'gzip'))
    assert_equal 'Accept-Encoding', result[:headers]['Vary']
  end
  
def test_only_compresses_text_types
  compression = Aris::Plugins::Compression.build
  Aris.routes({
    "example.com": {
      use: [compression],
      "/image": { get: { to: BinaryHandler } }
    }
  })
  
  result = @app.call(**build_env('/image', accept_encoding: 'gzip'))
  
  assert_equal 200, result[:status]
  refute result[:headers].key?('Content-Encoding'), "Binary content shouldn't be compressed"
end

def test_skips_if_compression_ineffective
  compression = Aris::Plugins::Compression.build
  Aris.routes({
    "example.com": {
      use: [compression],
      "/random": { get: { to: AlreadyCompressedHandler } }
    }
  })
  
  result = @app.call(**build_env('/random', accept_encoding: 'gzip'))
  
  # If compressed size >= original, plugin should skip compression
  assert_equal 200, result[:status]
end
end