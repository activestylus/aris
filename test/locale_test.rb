# test/locale_test.rb
require 'minitest/autorun'
require 'json'
require_relative '../lib/aris/core'
require_relative '../lib/aris/locale_injector'
require_relative '../lib/aris/route_helpers'
require_relative '../lib/aris/adapters/mock/adapter'
require_relative '../lib/aris/adapters/mock/request'
require_relative '../lib/aris/adapters/mock/response'

class LocaleTest < Minitest::Test
  def setup
    # Reset router before each test
    Aris::Router.send(:reset!)
  end

  # Test 1: Basic route expansion with locales
def test_expands_localized_routes
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "about" => {
        get: { 
          to: ->(_req, _params) { [200, {}, ["About page"]] },
          localized: { en: 'about', es: 'acerca' },
          as: :about
        }
      }
    }
  })
  
  # Test English route
  result_en = Aris::Router.match(
    domain: "example.com", 
    method: :get, 
    path: "/en/about"
  )
  assert result_en, "English route should match"
  assert_equal :en, result_en[:locale]
  assert_equal "example.com", result_en[:domain]
  
  # Test Spanish route
  result_es = Aris::Router.match(
    domain: "example.com", 
    method: :get, 
    path: "/es/acerca"
  )
  assert result_es, "Spanish route should match"
  assert_equal :es, result_es[:locale]
  assert_equal "example.com", result_es[:domain]
end

  # Test 2: Locale validation - error on undeclared locale
# In your test, the error message format changed
def test_validates_locale_in_domain_config
  assert_raises(Aris::Router::LocaleError) do
    Aris.routes(
      'example.com' => {
        locales: [:en, :es],
        'about' => {
          get: {
            to: ->(req, params) { [200, {}, ['About']] },
            as: :about,
            localized: {
              en: 'about',
              fr: 'a-propos'  # This should raise error - :fr not in [:en, :es]
            }
          }
        }
      }
    )
  end
end

# Test 3: Warning on incomplete locale coverage - FIXED
def test_warns_on_missing_locale_variants
  # Capture stderr (where warn writes to)
  original_stderr = $stderr
  $stderr = StringIO.new
  
  begin
    Aris.routes({
      "example.com" => {
        locales: [:en, :es, :fr],
        default_locale: :en,
        "about" => {
          get: { 
            to: ->(_req, _params) { [200, {}, []] },
            localized: { en: 'about', es: 'acerca' }  # Missing :fr
          }
        }
      }
    })
    
    # Get the warning output
    $stderr.rewind
    warning_output = $stderr.read
    
    # Check if warning was emitted
    assert warning_output.include?('missing locales'), "Should have warned about missing locales"
    assert warning_output.include?('fr'), "Should specifically mention :fr"
  ensure
    # Restore stderr
    $stderr = original_stderr
  end
end
  # Test 4: URL generation with locale
def test_url_generation_with_locale
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "/products" => {
        ":id" => {
          get: { 
            to: ->(_req, _params) { [200, {}, []] },
            localized: { en: 'products/:id', es: 'productos/:id' },
            as: :product
          }
        }
      }
    }
  })
  
  # Generate English path
  path_en = Aris.path("example.com", :product, id: 123, locale: :en)
  assert_equal "/en/products/123", path_en
  
  # Generate Spanish path
  path_es = Aris.path("example.com", :product, id: 123, locale: :es)
  assert_equal "/es/productos/123", path_es
end

  # Test 5: URL generation uses default locale when not specified
def test_url_generation_defaults_to_default_locale
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :es,
      "/about" => {
        get: { 
          to: ->(_req, _params) { [200, {}, []] },
          localized: { en: 'about', es: 'acerca' },
          as: :about
        }
      }
    }
  })
  
  # Without specifying locale, should use default (es)
  path = Aris.path("example.com", :about)
  assert_equal "/es/acerca", path
end
  # Test 6: Empty string for root path
def test_empty_string_generates_locale_root
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "" => {  # Empty string for root
        get: { 
          to: ->(_req, _params) { [200, {}, []] },
          localized: { en: '', es: '' },
          as: :home
        }
      }
    }
  })
  
  # Should match /en and /es
  result_en = Aris::Router.match(domain: "example.com", method: :get, path: "/en")
  assert result_en, "English root should match"
  assert_equal :en, result_en[:locale]
  
  result_es = Aris::Router.match(domain: "example.com", method: :get, path: "/es")
  assert result_es, "Spanish root should match"
  assert_equal :es, result_es[:locale]
end


  # Test 7: Root path redirect
  def test_root_path_redirects_to_default_locale
    adapter = Aris::Adapters::Mock::Adapter.new
    
    Aris.routes({
      "example.com" => {
        locales: [:en, :es],
        default_locale: :es,
        root_locale_redirect: true,
        "/" => {
          get: { 
            to: ->(_req, _params) { [200, {}, ["Home"]] },
            localized: { en: '', es: '' }
          }
        }
      }
    })
    
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'example.com'
    )
    
    assert_equal 302, response[:status]
    assert_equal '/es/', response[:headers]['Location']
  end

  # Test 8: Root redirect can be disabled
  def test_root_redirect_can_be_disabled
    Aris.routes({
      "example.com" => {
        locales: [:en, :es],
        default_locale: :es,
        root_locale_redirect: false,
        "/" => {
          get: { 
            to: ->(_req, _params) { [200, {}, ["Root"]] }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'example.com'
    )
    
    # Should NOT redirect, should execute handler
    assert_equal 200, response[:status]
  end

# Test 9: Request locale injection - FIXED
def test_request_locale_injection
  handler_called = false
  handler_request = nil
  
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "test" => {
        get: { 
          to: ->(req, _params) {
            handler_called = true
            handler_request = req
            [200, {}, ["OK"]]
          },
          localized: { en: 'test', es: 'prueba' }
        }
      }
    }
  })
  
  adapter = Aris::Adapters::Mock::Adapter.new
  response = adapter.call(
    method: :get,
    path: '/es/prueba',
    domain: 'example.com'
  )
  
  # Verify the handler was called
  assert handler_called, "Handler should have been called"
  assert handler_request, "Request should have been passed to handler"
  
  # Verify locale methods were injected
  assert_equal :es, handler_request.locale
  assert_equal [:en, :es], handler_request.available_locales
  assert_equal :en, handler_request.default_locale
end

  # Test 10: Multiple domains with different locales
  def test_different_locales_per_domain
    Aris.routes({
      "example.com" => {
        locales: [:en, :es],
        default_locale: :en,
        "/about" => {
          get: { 
            to: ->(_req, _params) { [200, {}, []] },
            localized: { en: 'about', es: 'acerca' }
          }
        }
      },
      "beispiel.de" => {
        locales: [:de, :en],
        default_locale: :de,
        "/about" => {
          get: { 
            to: ->(_req, _params) { [200, {}, []] },
            localized: { de: 'uber-uns', en: 'about' }
          }
        }
      }
    })
    
    # English domain
    result_en = Aris::Router.match(domain: "example.com", method: :get, path: "/en/about")
    assert result_en
    assert_equal :en, result_en[:locale]
    
    # German domain
    result_de = Aris::Router.match(domain: "beispiel.de", method: :get, path: "/de/uber-uns")
    assert result_de
    assert_equal :de, result_de[:locale]
    
    # Spanish on .com
    result_es = Aris::Router.match(domain: "example.com", method: :get, path: "/es/acerca")
    assert result_es
    assert_equal :es, result_es[:locale]
  end

  # Test 11: Non-localized and localized routes can coexist
def test_mixed_localized_and_non_localized_routes
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "about" => {
        get: { 
          to: ->(_req, _params) { [200, {}, ["About"]] },
          localized: { en: 'about', es: 'acerca' }
        }
      },
      "api" => {
        "status" => {
          get: { 
            to: ->(_req, _params) { [200, {}, ["Status"]] }
          }
        }
      }
    }
  })
  
  # Localized route
  result_localized = Aris::Router.match(domain: "example.com", method: :get, path: "/en/about")
  assert result_localized, "Localized route should match"
  assert_equal :en, result_localized[:locale]
  
  # Non-localized route
  result_non_localized = Aris::Router.match(domain: "example.com", method: :get, path: "/api/status")
  assert result_non_localized, "Non-localized route should match"
  assert_nil result_non_localized[:locale]
end

  # Test 12: Localized routes with parameters
def test_localized_routes_with_parameters
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "products" => {
        ":category" => {
          ":id" => {
            get: { 
              to: ->(_req, params) { [200, {}, [params.to_json]] },
              localized: { en: 'products/:category/:id', es: 'productos/:category/:id' },
              as: :product_detail
            }
          }
        }
      }
    }
  })
  
  # Match with parameters
  result = Aris::Router.match(
    domain: "example.com", 
    method: :get, 
    path: "/es/productos/electronics/123"
  )
  
  assert result, "Localized route with parameters should match"
  assert_equal :es, result[:locale]
  assert_equal 'electronics', result[:params][:category]
  assert_equal '123', result[:params][:id]
end

  # Test 13: Error when locale not available for named route
def test_error_when_locale_not_available
  Aris.routes({
    "example.com" => {
      locales: [:en, :es],
      default_locale: :en,
      "about" => {
        get: { 
          to: ->(_req, _params) { [200, {}, []] },
          localized: { en: 'about', es: 'acerca' },
          as: :about
        }
      }
    }
  })
  
  # This should raise LocaleError because :fr is not in the domain's locales
  error = assert_raises(Aris::Router::LocaleError) do
    Aris.path("example.com", :about, locale: :fr)
  end
  
  assert_match /fr/, error.message
  assert_match /not available/, error.message
end

  # Test 14: Domain config accessor
  def test_domain_config_accessor
    Aris.routes({
      "example.com" => {
        locales: [:en, :es, :fr],
        default_locale: :es,
        root_locale_redirect: false,
        "/" => {
          get: { to: ->(_req, _params) { [200, {}, []] } }
        }
      }
    })
    
    config = Aris::Router.domain_config("example.com")
    
    assert config
    assert_equal [:en, :es, :fr], config[:locales]
    assert_equal :es, config[:default_locale]
    assert_equal false, config[:root_locale_redirect]
  end
end
