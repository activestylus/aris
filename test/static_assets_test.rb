require_relative 'test_helper'

class StaticAssetsTest < Minitest::Test
  def setup
    # Create test files
    FileUtils.mkdir_p('public/test')
    File.write('public/test/style.css', 'body { color: red; }')
    File.write('public/test/script.js', 'console.log("hi");')
    File.write('public/test/image.jpg', 'fake-jpg-data')
    File.write('public/test/custom.flac', 'fake-flac-data')
    
    Aris.configure do |c|
      c.serve_static = true
    end
    
    Aris.routes({
      "example.com" => {
        "/" => { get: { to: ->(req, res, params) { res.html("Home") } } }
      }
    })
    
    @app = Aris::Adapters::RackApp.new
  end
  
  def teardown
    FileUtils.rm_rf('public/test')
    Aris::Config.serve_static = false
    Aris::Config.instance_variable_set(:@mime_types, nil) # Reset
  end
  
  def test_serves_css_with_correct_mime_type
    response = @app.call(build_env('/test/style.css'))
    
    assert_equal 200, response[0]
    assert_equal 'text/css', response[1]['content-type']
    assert_equal 'body { color: red; }', response[2].first
  end
  
  def test_serves_js_with_correct_mime_type
    response = @app.call(build_env('/test/script.js'))
    
    assert_equal 200, response[0]
    assert_equal 'application/javascript', response[1]['content-type']
    assert_equal 'console.log("hi");', response[2].first
  end
  
  def test_serves_images_with_correct_mime_type
    response = @app.call(build_env('/test/image.jpg'))
    
    assert_equal 200, response[0]
    assert_equal 'image/jpeg', response[1]['content-type']
    assert_equal 'fake-jpg-data', response[2].first
  end
  
  def test_returns_404_for_non_existent_files
    response = @app.call(build_env('/test/nonexistent.css'))
    
    assert_equal 404, response[0]
  end
  
  def test_bypasses_static_serving_when_disabled
    Aris::Config.serve_static = false
    
    response = @app.call(build_env('/test/style.css'))
    
    # Should hit 404 handler, not serve the file
    assert_equal 404, response[0]
  end
  
  def test_routes_take_precedence_over_files
    # Even if file exists, defined route should win
    File.write('public/index.html', '<h1>Static</h1>')
    
    response = @app.call(build_env('/'))
    
    assert_equal 200, response[0]
    assert_includes response[2].first, 'Home'
    
    FileUtils.rm('public/index.html')
  end
  
  def test_custom_mime_types
    Aris::Config.mime_types = { '.flac' => 'audio/flac' }
    
    response = @app.call(build_env('/test/custom.flac'))
    
    assert_equal 200, response[0]
    assert_equal 'audio/flac', response[1]['content-type']
  end
  
  def test_unknown_extension_returns_octet_stream
    File.write('public/test/unknown.xyz', 'data')
    
    response = @app.call(build_env('/test/unknown.xyz'))
    
    assert_equal 'application/octet-stream', response[1]['content-type']
    
    FileUtils.rm('public/test/unknown.xyz')
  end
  
  def test_only_serves_get_requests
    response = @app.call(build_env('/test/style.css', 'POST'))
    
    assert_equal 404, response[0]
  end
  
  private
  
  def build_env(path, method = 'GET')
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new
    }
  end
end