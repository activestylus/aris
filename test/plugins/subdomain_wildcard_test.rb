# test/features/subdomain_test.rb
require 'minitest/autorun'
require_relative '../../lib/aris'

class SubdomainTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
  end

def test_subdomain_wildcard_routing
  
  Aris.routes({
    "*.example.com" => {
      "/" => {
        get: {
          to: ->(req, res, params) {
            subdomain = req.respond_to?(:subdomain) ? req.subdomain : "NO_SUBDOMAIN_METHOD"
            res.text("Subdomain: #{subdomain}")
          }
        }
      }
    }
  })
  
  adapter = Aris::Adapters::Mock::Adapter.new
  
  response = adapter.call(
    method: :get,
    path: '/',
    domain: 'acme.example.com'
  )
  
  
  assert_equal 200, response[:status]
  assert_equal "Subdomain: acme", response[:body].first
end
  
  def test_subdomain_available_in_params
    Aris.routes({
      "*.api.com" => {
        "/users" => {
          get: {
            to: ->(req, res, params) {
              res.json({
                subdomain: req.subdomain,
                param_subdomain: params[:subdomain]
              })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    response = adapter.call(
      method: :get,
      path: '/users',
      domain: 'v1.api.com'
    )
    
    assert_equal 200, response[:status]
    data = JSON.parse(response[:body].first)
    assert_equal "v1", data["subdomain"]
    assert_equal "v1", data["param_subdomain"]
  end
  
  def test_complex_subdomains
    Aris.routes({
      "*.app.example.com" => {
        "/" => {
          get: {
            to: ->(req, res, params) {
              res.text("Complex: #{req.subdomain}")
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'tenant.staging.app.example.com'
    )
    
    assert_equal 200, response[:status]
    assert_equal "Complex: tenant.staging", response[:body].first
  end
# Let's add debug to the specific failing test
def test_wildcard_subdomain_matching
  Aris.routes({
    "*.example.com" => {
      "/" => {
        get: {
          to: ->(req, res, params) {
            # Minimal check - does the request have subdomain method?
            has_subdomain = req.respond_to?(:subdomain)
            subdomain_value = has_subdomain ? req.subdomain : "no_method"
            res.text("Has subdomain method: #{has_subdomain}, Value: #{subdomain_value}")
          }
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
  
  # Just check the response to see what it says
  if response[:status] == 500
    # The error might be in the error handler, not our code
  end
  
  assert_equal 200, response[:status]
end
end