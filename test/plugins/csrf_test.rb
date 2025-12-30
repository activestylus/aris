require_relative '../test_helper'

class FormSubmitSuccess
  def self.call(request, params)
    "Form Submitted"
  end
end

class CsrfFullFlowTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    
    # Use the registered symbol - it resolves to the classes automatically
    Aris.routes({
      "example.com": {
        use: [:csrf], # ← Clean! Resolves to both generator and protection
        "/form": {
          get: { to: FormSubmitSuccess, as: :form_page },
          post: { to: FormSubmitSuccess, as: :form_submit }
        }
      }
    })
    
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def build_env(path, method, csrf_token: nil)
    headers = {}
    headers['HTTP_X_CSRF_TOKEN'] = csrf_token if csrf_token
    
    {
      method: method.to_s.upcase,
      path: path,
      domain: 'example.com',
      headers: headers,
      body: ''
    }
  end
  
  def teardown
    Thread.current[Aris::Plugins::CSRF_THREAD_KEY] = nil
  end
  
  def test_01_generator_stores_token_on_get_request
    @app.call(**build_env('/form', :get))
    
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    assert token.is_a?(String), "Token not stored"
    assert token.length > 20, "Token too short"
  end
  
  def test_02_post_request_halts_without_valid_token
    @app.call(**build_env('/form', :get))
    stored_token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    result = @app.call(**build_env('/form', :post, csrf_token: 'INVALID'))
    
    assert_equal 403, result[:status]
    assert_match /CSRF/, result[:body].first
  end
  
  def test_03_post_request_succeeds_with_valid_token
    # Set token via GET
    @app.call(**build_env('/form', :get))
    valid_token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    # POST with valid token
    result = @app.call(**build_env('/form', :post, csrf_token: valid_token))
    
    assert_equal 200, result[:status]
    assert_equal "Form Submitted", result[:body].first
  end
end