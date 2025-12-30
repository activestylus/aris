# test/features/subdomain_test.rb
require 'minitest/autorun'
require_relative '../lib/aris'

class SubdomainTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
  end

  def test_wildcard_subdomain_matching
    Aris.routes({
      "*.example.com" => {
        "/" => {
          get: {
            to: ->(req, res, params) {
              subdomain = req.subdomain
              res.text("Subdomain: #{subdomain}")
            }
          }
        }
      },
      "www.example.com" => {
        "/" => {
          get: {
            to: ->(req, res, params) {
              res.text("Main website")
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Test wildcard subdomain
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'acme.example.com'
    )
    
    assert_equal 200, response[:status]
    assert_equal "Subdomain: acme", response[:body].first
    
    # Test specific subdomain (should take precedence)
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'www.example.com'
    )
    
    assert_equal 200, response[:status]
    assert_equal "Main website", response[:body].first
    
    # Test no subdomain case
    response = adapter.call(
      method: :get,
      path: '/', 
      domain: 'example.com'
    )
    
    assert_equal 200, response[:status]
    assert_equal "Subdomain: ", response[:body].first # Empty string or nil?
  end
  
  def test_subdomain_in_params
    Aris.routes({
      "*.api.com" => {
        "/users" => {
          get: {
            to: ->(req, res, params) {
              subdomain_from_method = req.subdomain
              subdomain_from_params = params[:subdomain]
              res.json({
                from_method: subdomain_from_method,
                from_params: subdomain_from_params
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
    assert_equal "v1", data["from_method"]
    assert_equal "v1", data["from_params"]
  end
  
  def test_multiple_subdomain_levels
    Aris.routes({
      "*.example.com" => {
        "/" => {
          get: {
            to: ->(req, res, params) {
              res.text("Subdomain: #{req.subdomain}")
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Multi-level subdomain
    response = adapter.call(
      method: :get,
      path: '/',
      domain: 'app.staging.example.com'
    )
    
    assert_equal 200, response[:status]
    assert_equal "Subdomain: app.staging", response[:body].first
  end
end