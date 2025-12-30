# test/plugins/cookies_test.rb
require 'minitest/autorun'
require_relative '../../lib/aris'

class CookieTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
    
    # Reset config to defaults
    Aris::Config.reset!
    
    # Configure for testing
    Aris.configure do |config|
      config.secret_key_base = 'test_secret_key_base_32_bytes_long!'
      config.cookie_options = {
        httponly: true,
        secure: false,
        same_site: :lax,
        path: '/'
      }
    end
  end

def test_basic_cookies_read_and_write
  Aris.routes({
    "example.com" => {
      use: [:cookies],
      "/set-cookie" => {
        get: {
          to: ->(req, res, params) {
            # Use the cookie helper
            res.set_cookie('user_id', '123')
            res.text("Cookie set")
          }
        }
      },
      "/read-cookie" => {
        get: {
          to: ->(req, res, params) {
            # Read from Rack cookies (should be available by default)
            user_id = req.cookies['user_id'] if req.respond_to?(:cookies)
            res.text("User: #{user_id}")
          }
        }
      }
    }
  })

  adapter = Aris::Adapters::Mock::Adapter.new

  # First request - set cookie
  response1 = adapter.call(
    method: :get,
    path: '/set-cookie',
    domain: 'example.com'
  )

  assert_equal 200, response1[:status]
  set_cookie_header = response1[:headers]['Set-Cookie']
  assert set_cookie_header, "Should set cookie"
  assert_match(/user_id=123/, set_cookie_header)

  # Second request - read cookie (simulate browser sending cookie)
  response2 = adapter.call(
    method: :get,
    path: '/read-cookie',
    domain: 'example.com',
    headers: { 'Cookie' => 'user_id=123' }
  )

  assert_equal 200, response2[:status]
  assert_includes response2[:body].first, 'User: 123'
end
  def test_cookie_with_options
    Aris.routes({
      "example.com" => {
        use: [:cookies],
        "/secure-cookie" => {
          get: {
            to: ->(req, res, params) {
              res.set_cookie('session', 'abc123', {
                httponly: true,
                max_age: 3600,
                path: '/admin'
              })
              res.text("Cookie set")
            }
          }
        }
      }
    })

    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/secure-cookie',
      domain: 'example.com'
    )

    assert_equal 200, response[:status]
    set_cookie = response[:headers]['Set-Cookie']
    assert_match(/session=abc123/, set_cookie)
    assert_match(/HttpOnly/, set_cookie)
    assert_match(/Max-Age=3600/, set_cookie)
    assert_match(/Path=\/admin/, set_cookie)
  end

  def test_delete_cookie
    Aris.routes({
      "example.com" => {
        use: [:cookies],
        "/delete-cookie" => {
          get: {
            to: ->(req, res, params) {
              res.delete_cookie('user_id')
              res.text("Cookie deleted")
            }
          }
        }
      }
    })

    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/delete-cookie',
      domain: 'example.com'
    )

    assert_equal 200, response[:status]
    set_cookie = response[:headers]['Set-Cookie']
    assert_match(/user_id=;/, set_cookie)
    assert_match(/Max-Age=0/, set_cookie) || assert_match(/Expires=/, set_cookie)
  end

def test_cookie_methods_exist_with_plugin
  Aris.routes({
    "example.com" => {
      use: [:cookies],
      "/check-methods" => {
        get: {
          to: ->(req, res, params) {
            has_set_cookie = res.respond_to?(:set_cookie)
            has_delete_cookie = res.respond_to?(:delete_cookie)
            res.json({
              set_cookie: has_set_cookie,
              delete_cookie: has_delete_cookie
            })
          }
        }
      }
    }
  })

  adapter = Aris::Adapters::Mock::Adapter.new
  response = adapter.call(
    method: :get,
    path: '/check-methods',
    domain: 'example.com'
  )

  assert_equal 200, response[:status]
  data = JSON.parse(response[:body].first)
  assert data['set_cookie'], "Should have set_cookie method"
  assert data['delete_cookie'], "Should have delete_cookie method"
end
def test_cookies_without_plugin
  # This test should NOT use the cookies plugin
  Aris.routes({
    "example.com" => {
      "/no-cookie-plugin" => {
        get: {
          to: ->(req, res, params) {
            # Test that we can still respond without the plugin
            # The response object won't have set_cookie method
            has_set_cookie = res.respond_to?(:set_cookie)
            res.text("Has set_cookie: #{has_set_cookie}")
          }
        }
      }
    }
  })

  adapter = Aris::Adapters::Mock::Adapter.new
  response = adapter.call(
    method: :get,
    path: '/no-cookie-plugin',
    domain: 'example.com'
  )

  assert_equal 200, response[:status]
  assert_includes response[:body].first, 'Has set_cookie: false'
end

  def test_cookie_default_options_from_config
    # Test that default cookie options are applied from config
    Aris.configure do |config|
      config.cookie_options = {
        httponly: true,
        secure: false,
        same_site: 'Strict',
        path: '/app'
      }
    end

    Aris.routes({
      "example.com" => {
        use: [:cookies],
        "/default-options" => {
          get: {
            to: ->(req, res, params) {
              res.set_cookie('test', 'value')
              res.text("Cookie with defaults")
            }
          }
        }
      }
    })

    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/default-options',
      domain: 'example.com'
    )

    assert_equal 200, response[:status]
    set_cookie = response[:headers]['Set-Cookie']
    assert_match(/HttpOnly/, set_cookie)
    assert_match(/Path=\/app/, set_cookie)
    assert_match(/SameSite=Strict/, set_cookie)
  end

  def test_cookie_overriding_default_options
    Aris.configure do |config|
      config.cookie_options = {
        httponly: true,
        secure: true,
        path: '/default'
      }
    end

    Aris.routes({
      "example.com" => {
        use: [:cookies],
        "/override-options" => {
          get: {
            to: ->(req, res, params) {
              res.set_cookie('test', 'value', {
                httponly: false,  # Override default
                path: '/custom',  # Override default
                max_age: 1000     # Add new option
              })
              res.text("Cookie with overrides")
            }
          }
        }
      }
    })

    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/override-options',
      domain: 'example.com'
    )

    assert_equal 200, response[:status]
    set_cookie = response[:headers]['Set-Cookie']
    refute_match(/HttpOnly/, set_cookie, "Should override httponly default")
    assert_match(/Path=\/custom/, set_cookie, "Should override path default")
    assert_match(/Max-Age=1000/, set_cookie, "Should include new option")
  end

end