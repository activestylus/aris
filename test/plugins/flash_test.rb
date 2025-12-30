# test/plugins/flash_test.rb
require 'minitest/autorun'
require_relative '../../lib/aris'

class FlashTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
    
    # Configure for testing
    Aris.configure do |config|
      config.secret_key_base = 'test_secret_key_base_32_bytes_long!'
    end
    
    # Register plugins directly (remove the plugins check)
    Aris.register_plugin(:cookies, plugin_class: Aris::Plugins::Cookies)
    Aris.register_plugin(:flash, plugin_class: Aris::Plugins::Flash)
  end
def test_debug_plugin_registration
  
  # Try to register cookies plugin
  begin
    Aris.register_plugin(:cookies, plugin_class: Aris::Plugins::Cookies)
  rescue => e
    puts "Error registering cookies plugin: #{e.message}"
  end
  
  # Try to register flash plugin
  begin
    Aris.register_plugin(:flash, plugin_class: Aris::Plugins::Flash)
  rescue => e
    puts "Error registering flash plugin: #{e.message}"
  end
end
  def test_flash_persistence_across_redirect
    Aris.routes({
      "example.com" => {
        use: [:cookies, :flash],
        "/set-flash" => {
          get: {
            to: ->(req, res, params) {
              req.flash[:notice] = "User created successfully!"
              req.flash[:user_id] = 123
              res.redirect("/read-flash")
            }
          }
        },
        "/read-flash" => {
          get: {
            to: ->(req, res, params) {
              notice = req.flash[:notice]
              user_id = req.flash[:user_id]
              res.json({ notice: notice, user_id: user_id })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # First request - set flash and redirect
    response1 = adapter.call(
      method: :get,
      path: '/set-flash',
      domain: 'example.com'
    )
    
    assert_equal 302, response1[:status]
    
    # Extract flash cookie from first response
    set_cookie = response1[:headers]['Set-Cookie']
    assert set_cookie, "Should set flash cookie"
    
    # Extract cookie for the next request
    cookie_header = set_cookie.split(', ').find { |c| c.include?('_aris_flash') }
    assert cookie_header, "Should have flash cookie"
    
    cookie_value = cookie_header.match(/_aris_flash=([^;]+)/)[1]
    
    # Second request - read flash (simulate browser following redirect)
    response2 = adapter.call(
      method: :get,
      path: '/read-flash',
      domain: 'example.com',
      headers: { 'Cookie' => "_aris_flash=#{cookie_value}" }
    )
    
    assert_equal 200, response2[:status]
    data = JSON.parse(response2[:body].first)
    assert_equal "User created successfully!", data["notice"]
    assert_equal 123, data["user_id"]
    
    # Flash should be cleared after reading
    assert response2[:headers]['Set-Cookie'], "Should clear flash after reading"
    assert_match(/Max-Age=0/, response2[:headers]['Set-Cookie']) || 
     assert_match(/Expires=/, response2[:headers]['Set-Cookie'])
  end
  
def test_flash_now_only_for_current_request
  Aris.routes({
    "example.com" => {
      use: [:cookies, :flash],
      "/flash-now" => {
        get: {
          to: ->(req, res, params) {
            req.flash.now[:error] = "This won't persist to next request"
            current_error = req.flash.now[:error]
            res.text("Current: #{current_error}")
          }
        }
      }
    }
  })
  
  adapter = Aris::Adapters::Mock::Adapter.new
  response = adapter.call(
    method: :get,
    path: '/flash-now',
    domain: 'example.com'
  )
  
  assert_equal 200, response[:status]
  assert_equal "Current: This won't persist to next request", response[:body].first
  
  # Verify no flash data is stored for next request
  set_cookie = response[:headers]['Set-Cookie']
  refute set_cookie&.include?('_aris_flash'), "flash.now should not set cookie for next request"
end
def test_flash_cleared_after_reading
  Aris.routes({
    "example.com" => {
      use: [:cookies, :flash],
      "/read-twice" => {
        get: {
          to: ->(req, res, params) {
            first_read = req.flash[:message]
            second_read = req.flash[:message] # Should be nil after first read
            res.json({ first: first_read, second: second_read })
          }
        }
      }
    }
  })
  
  # Create initial flash data
  flash_data = { message: "Hello, this will be cleared after first read" }
  
  adapter = Aris::Adapters::Mock::Adapter.new
  response = adapter.call(
    method: :get,
    path: '/read-twice',
    domain: 'example.com',
    headers: { 'Cookie' => "_aris_flash=#{Base64.urlsafe_encode64(flash_data.to_json)}" }
  )
  
  assert_equal 200, response[:status]
  data = JSON.parse(response[:body].first)
  assert_equal "Hello, this will be cleared after first read", data["first"]
  assert_nil data["second"], "Flash should be cleared after first read"
  
  # Should clear the cookie after reading
  assert response[:headers]['Set-Cookie']&.include?('_aris_flash'), "Should clear flash cookie"
end
  
def test_flash_now_vs_regular_flash
  Aris.routes({
    "example.com" => {
      use: [:cookies, :flash],
      "/test-both-set" => {
        get: {
          to: ->(req, res, params) {
            req.flash[:persistent] = "I persist across redirects"
            req.flash.now[:temporary] = "I only exist this request"
            res.redirect("/test-both-read")
          }
        }
      },
      "/test-both-read" => {
        get: {
          to: ->(req, res, params) {
            persistent = req.flash[:persistent]  # Should exist (from previous request)
            temporary = req.flash[:temporary]    # Should be nil (flash.now doesn't persist)
            res.json({
              persistent: persistent,
              temporary: temporary
            })
          }
        }
      }
    }
  })
  
  adapter = Aris::Adapters::Mock::Adapter.new
  
  # First request - set both types of flash
  response1 = adapter.call(
    method: :get,
    path: '/test-both-set',
    domain: 'example.com'
  )
  
  assert_equal 302, response1[:status]
  
  # Extract flash cookie for next request
  set_cookie = response1[:headers]['Set-Cookie']
  assert set_cookie, "Should set cookie for persistent flash"
  
  cookie_header = set_cookie.split(', ').find { |c| c.include?('_aris_flash') }
  cookie_value = cookie_header.match(/_aris_flash=([^;]+)/)[1]
  
  # Decode to verify only persistent data is stored
  decoded = Base64.urlsafe_decode64(cookie_value)
  stored_data = JSON.parse(decoded)
  assert_equal "I persist across redirects", stored_data["persistent"]
  refute stored_data.key?("temporary"), "flash.now data should not be stored"
  
  # Second request - read flash (should only have persistent, not temporary)
  response2 = adapter.call(
    method: :get,
    path: '/test-both-read',
    domain: 'example.com',
    headers: { 'Cookie' => "_aris_flash=#{cookie_value}" }
  )
  
  assert_equal 200, response2[:status]
  data = JSON.parse(response2[:body].first)
  assert_equal "I persist across redirects", data["persistent"]
  assert_nil data["temporary"], "flash.now should not persist to next request"
end
  def test_multiple_flash_messages
    Aris.routes({
      "example.com" => {
        use: [:cookies, :flash],
        "/multiple" => {
          get: {
            to: ->(req, res, params) {
              req.flash[:notice] = "Success message"
              req.flash[:error] = "Error message" 
              req.flash[:info] = "Info message"
              res.redirect("/read-multiple")
            }
          }
        },
        "/read-multiple" => {
          get: {
            to: ->(req, res, params) {
              notice = req.flash[:notice]
              error = req.flash[:error]
              info = req.flash[:info]
              res.json({ notice: notice, error: error, info: info })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Set multiple flash messages
    response1 = adapter.call(
      method: :get,
      path: '/multiple',
      domain: 'example.com'
    )
    
    # Read multiple flash messages
    cookie_header = response1[:headers]['Set-Cookie'].split(', ').find { |c| c.include?('_aris_flash') }
    cookie_value = cookie_header.match(/_aris_flash=([^;]+)/)[1]
    
    response2 = adapter.call(
      method: :get,
      path: '/read-multiple',
      domain: 'example.com',
      headers: { 'Cookie' => "_aris_flash=#{cookie_value}" }
    )
    
    assert_equal 200, response2[:status]
    data = JSON.parse(response2[:body].first)
    assert_equal "Success message", data["notice"]
    assert_equal "Error message", data["error"]
    assert_equal "Info message", data["info"]
  end
  
  def test_flash_without_plugin_raises_error
    # Test that flash is not available without the plugin
    Aris.routes({
      "example.com" => {
        "/no-flash-plugin" => {
          get: {
            to: ->(req, res, params) {
              has_flash = req.respond_to?(:flash)
              res.json({ has_flash: has_flash })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/no-flash-plugin',
      domain: 'example.com'
    )
    
    assert_equal 200, response[:status]
    data = JSON.parse(response[:body].first)
    refute data["has_flash"], "Flash should not be available without plugin"
  end

end