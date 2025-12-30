require 'minitest/autorun'
require_relative '../lib/aris'

class TrailingSlashTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris::Config.reset!
  end
  
  def test_strict_mode_default
    assert_equal :strict, Aris::Config.trailing_slash
  end
  
  def test_redirect_mode
    Aris.configure do |config|
      config.trailing_slash = :redirect
    end
    
    Aris.routes({
      "example.com" => {
        "/about" => { get: { to: ->(_req, _res) { [200, {}, ["About"]] } } }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Trailing slash redirects
    response = adapter.call(method: :get, path: '/about/', domain: 'example.com')
    assert_equal 301, response[:status]
    assert_equal '/about', response[:headers]['Location']
    
    # No trailing slash works
    response = adapter.call(method: :get, path: '/about', domain: 'example.com')
    assert_equal 200, response[:status]
  end
  
  def test_ignore_mode
    Aris.configure do |config|
      config.trailing_slash = :ignore
    end
    
    Aris.routes({
      "example.com" => {
        "/about" => { get: { to: ->(_req, _res) { [200, {}, ["About"]] } } }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Both work
    response = adapter.call(method: :get, path: '/about/', domain: 'example.com')
    assert_equal 200, response[:status]
    
    response = adapter.call(method: :get, path: '/about', domain: 'example.com')
    assert_equal 200, response[:status]
  end
  
  def test_strict_mode
    Aris.configure do |config|
      config.trailing_slash = :strict
    end
    
    Aris.routes({
      "example.com" => {
        "/about" => { get: { to: ->(_req, _res) { [200, {}, ["About"]] } } }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # No trailing slash works
    response = adapter.call(method: :get, path: '/about', domain: 'example.com')
    assert_equal 200, response[:status]
    
    # Trailing slash is different route (404)
    response = adapter.call(method: :get, path: '/about/', domain: 'example.com')
    assert_equal 404, response[:status]
  end
  
  def test_custom_redirect_status
    Aris.configure do |config|
      config.trailing_slash = :redirect
      config.trailing_slash_status = 302
    end
    
    Aris.routes({
      "example.com" => {
        "/about" => { get: { to: ->(_req, _res) { [200, {}, ["About"]] } } }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(method: :get, path: '/about/', domain: 'example.com')
    
    assert_equal 302, response[:status]
  end
  
  def test_root_path_unaffected
    Aris.configure do |config|
      config.trailing_slash = :redirect
    end
    
    Aris.routes({
      "example.com" => {
        "/" => { get: { to: ->(_req, _res) { [200, {}, ["Home"]] } } }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Root with trailing slash works (not redirected)
    response = adapter.call(method: :get, path: '/', domain: 'example.com')
    assert_equal 200, response[:status]
  end
end