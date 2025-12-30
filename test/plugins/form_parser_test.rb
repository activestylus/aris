# test/plugins/form_parser_test.rb
require_relative '../test_helper'
class FormHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@form_data)
    if data
      "Received: #{data.inspect}"
    else
      "No form data"
    end
  end
end
class FormParserTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    
    Aris.routes({
      "example.com": {
        use: [Aris::Plugins::FormParser.build],
        "/submit": {
          post: { to: FormHandler },
          put: { to: FormHandler },
          patch: { to: FormHandler },
          get: { to: FormHandler }
        }
      }
    })
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'POST', body: nil, content_type: 'application/x-www-form-urlencoded')
    headers = {}
    headers['CONTENT_TYPE'] = content_type if content_type
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'example.com',
      headers: headers,
      body: body || ''
    }
  end
  
  def test_simple_form_data
    body = 'username=alice&email=alice@example.com'
    result = @app.call(**build_env('/submit', body: body))
    assert_equal 200, result[:status]
    assert_match /alice/, result[:body].first
    assert_match /alice@example.com/, result[:body].first
  end

  def test_nested_parameters
    body = 'user[name]=bob&user[email]=bob@example.com&user[age]=30'
    result = @app.call(**build_env('/submit', body: body))
    assert_equal 200, result[:status]
    assert_match /bob/, result[:body].first
    assert_match /bob@example.com/, result[:body].first
    assert_match /30/, result[:body].first
  end

  def test_array_parameters
    body = 'tags[]=ruby&tags[]=rails&tags[]=web'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /ruby/, result[:body].first
    assert_match /rails/, result[:body].first
    assert_match /web/, result[:body].first
  end

  def test_url_encoded_special_characters
    body = 'message=Hello+World%21&name=Alice+%26+Bob'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /Hello World!/, result[:body].first
    assert_match /Alice & Bob/, result[:body].first
  end

  def test_put_method
    body = 'title=Updated+Title'
    result = @app.call(**build_env('/submit', method: 'PUT', body: body))
    assert_equal 200, result[:status]
    assert_match /Updated Title/, result[:body].first
  end

  def test_patch_method
    body = 'status=active'
    result = @app.call(**build_env('/submit', body: body, method: 'PATCH'))
    assert_equal 200, result[:status]
    assert_match /active/, result[:body].first
  end

  def test_get_skips_parsing
    body = 'username=alice'
    result = @app.call(**build_env('/submit', body: body, method: 'GET'))
    assert_equal 200, result[:status]
    assert_equal "No form data", result[:body].first
  end

  def test_wrong_content_type_skips_parsing
    body = 'username=alice'
    result = @app.call(**build_env('/submit', body: body,content_type: 'application/json'))
    assert_equal 200, result[:status]
    assert_equal "No form data", result[:body].first
  end

  def test_empty_body_skips_parsing
    result = @app.call(**build_env('/submit', body: ''))
    assert_equal 200, result[:status]
    assert_equal "No form data", result[:body].first
  end

  def test_nil_body_skips_parsing
    result = @app.call(**build_env('/submit', body: nil))
    assert_equal 200, result[:status]
    assert_equal "No form data", result[:body].first
  end

  def test_multiple_values_same_key
    body = 'color=red&color=blue&color=green'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /green/, result[:body].first
  end

  def test_empty_values
    body = 'name=alice&description=&tags='
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /alice/, result[:body].first
  end

  def test_complex_nested_structure
    body = 'user[profile][name]=alice&user[profile][age]=25&user[settings][theme]=dark'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /alice/, result[:body].first
    assert_match /25/, result[:body].first
    assert_match /dark/, result[:body].first
  end

  def test_numbers_as_strings
    body = 'age=30&price=19.99&count=5'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /30/, result[:body].first
    assert_match /19.99/, result[:body].first
    assert_match /5/, result[:body].first
  end

  def test_boolean_like_values
    body = 'active=true&verified=false&premium=1'
    result = @app.call(**build_env('/submit', body: body))
    
    assert_equal 200, result[:status]
    assert_match /true/, result[:body].first
    assert_match /false/, result[:body].first
    assert_match /1/, result[:body].first
  end

  def test_content_type_with_charset
    body = 'name=alice'
    result = @app.call(**build_env('/submit', body: body, content_type: 'application/x-www-form-urlencoded; charset=UTF-8'))
    assert_equal 200, result[:status]
    assert_match /alice/, result[:body].first
  end

  def test_large_form_data
    fields = 100.times.map { |i| "field#{i}=value#{i}" }
    body = fields.join('&')
    result = @app.call(**build_env('/submit', body: body))
    assert_equal 200, result[:status]
    assert_match /value0/, result[:body].first
    assert_match /value99/, result[:body].first
  end
end