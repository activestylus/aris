# test/plugins/json_test.rb
require_relative '../test_helper'

class JsonParserHandler
  def self.call(request, params)
    # Access the parsed JSON data
    data = request.json_body
    if data
      "Received: #{data.inspect}"
    else
      "No JSON data"
    end
  end
end

class JsonParserTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "api.example.com"
    
    Aris.routes({
      "api.example.com": {
        use: [:json],
        "/data": {
          post: { to: JsonParserHandler },
          put: { to: JsonParserHandler },
          patch: { to: JsonParserHandler },
          get: { to: JsonParserHandler }
        }
      }
    })
    
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method, body: nil, content_type: 'application/json')
    headers = {}
    headers['CONTENT_TYPE'] = content_type if content_type
    
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'api.example.com',
      headers: headers,
      body: body || ''
    }
  end
  
  def test_post_with_valid_json
    json_body = JSON.generate({ name: 'Alice', age: 30 })
    result = @app.call(**build_env('/data', :post, body: json_body))
    assert_equal 200, result[:status]
    assert_match /Alice/, result[:body].first
    assert_match /30/, result[:body].first
  end

  def test_put_with_valid_json
    json_body = JSON.generate({ title: 'Updated' })
    result = @app.call(**build_env('/data', :post, body: json_body))
    assert_equal 200, result[:status]
    assert_match /Updated/, result[:body].first
  end

  def test_patch_with_valid_json
    json_body = JSON.generate({ status: 'active' })
    result = @app.call(**build_env('/data', :patch, body: json_body))
    assert_equal 200, result[:status]
    assert_match /active/, result[:body].first
  end

  def test_get_skips_json_parsing
    json_body = JSON.generate({ data: 'test' })
    result = @app.call(**build_env('/data', :get, body: json_body))
    assert_equal 200, result[:status]
    assert_equal "No JSON data", result[:body].first
  end

  def test_empty_body_skips_parsing
    result = @app.call(**build_env('/data', :post, body: ''))
    assert_equal 200, result[:status]
    assert_equal "No JSON data", result[:body].first
  end

  def test_nil_body_skips_parsing
    result = @app.call(**build_env('/data', :post, body: nil))
    assert_equal 200, result[:status]
    assert_equal "No JSON data", result[:body].first
  end

  def test_invalid_json_returns_400
    result = @app.call(**build_env('/data', :post, body: '{invalid json}'))
    assert_equal 400, result[:status]
    assert_equal 'application/json', result[:headers]['content-type']
    error = JSON.parse(result[:body].first)
    assert_equal 'Invalid JSON', error['error']
    assert error['message'].length > 0
  end

  def test_malformed_json_returns_400
    result = @app.call(**build_env('/data', :post, body: '{"name": "Alice"'))
    assert_equal 400, result[:status]
    error = JSON.parse(result[:body].first)
    assert_equal 'Invalid JSON', error['error']
  end

  def test_nested_json_structures
    json_body = JSON.generate({
      user: {
        name: 'Bob',
        address: {
          city: 'New York',
          zip: '10001'
        }
      }
    })
    result = @app.call(**build_env('/data', :post, body: json_body))
    assert_equal 200, result[:status]
    assert_match /Bob/, result[:body].first
    assert_match /New York/, result[:body].first
  end

  def test_json_arrays
    json_body = JSON.generate([1, 2, 3, 4, 5])
    result = @app.call(**build_env('/data', :post, body: json_body))    
    assert_equal 200, result[:status]
    assert_match /\[1, 2, 3, 4, 5\]/, result[:body].first
  end

  def test_special_characters_preserved
    json_body = JSON.generate({ message: "Hello\nWorld\t!" })
    result = @app.call(**build_env('/data', :post, body: json_body))
    assert_equal 200, result[:status]
    assert_match /Hello/, result[:body].first
  end
end