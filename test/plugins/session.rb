# test/plugins/session_test.rb
require 'minitest/autorun'
require_relative '../../lib/aris'

class SessionTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
    
    Aris.configure do |config|
      config.secret_key_base = 'test_secret_key_base_32_bytes_long!'
    end
    
    Aris.register_plugin(:cookies, plugin_class: Aris::Plugins::Cookies)
    Aris.register_plugin(:session, plugin_class: Aris::Plugins::Session)
  end

  def test_session_storage
    Aris.routes({
      "example.com" => {
        use: [:cookies, :session],
        "/login" => {
          post: {
            to: ->(req, res, params) {
              req.session[:user_id] = 123
              req.session[:role] = 'admin'
              res.text("Logged in")
            }
          }
        },
        "/profile" => {
          get: {
            to: ->(req, res, params) {
              user_id = req.session[:user_id]
              role = req.session[:role]
              res.json({ user_id: user_id, role: role })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Login and set session
    response1 = adapter.call(
      method: :post,
      path: '/login',
      domain: 'example.com'
    )
    
    assert_equal 200, response1[:status]
    set_cookie = response1[:headers]['Set-Cookie']
    assert set_cookie, "Should set session cookie"
    
    # Access profile with session
    cookie_header = set_cookie.split(', ').find { |c| c.include?('_aris_session') }
    cookie_value = cookie_header.match(/_aris_session=([^;]+)/)[1]
    
    response2 = adapter.call(
      method: :get,
      path: '/profile',
      domain: 'example.com',
      headers: { 'Cookie' => "_aris_session=#{cookie_value}" }
    )
    
    assert_equal 200, response2[:status]
    data = JSON.parse(response2[:body].first)
    assert_equal 123, data["user_id"]
    assert_equal "admin", data["role"]
  end
  
  def test_session_logout
    Aris.routes({
      "example.com" => {
        use: [:cookies, :session],
        "/logout" => {
          post: {
            to: ->(req, res, params) {
              req.session.destroy
              res.text("Logged out")
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Logout should clear session
    response = adapter.call(
      method: :post,
      path: '/logout',
      domain: 'example.com'
    )
    
    assert_equal 200, response[:status]
    set_cookie = response[:headers]['Set-Cookie']
    assert set_cookie, "Should clear session cookie"
    assert_match(/Max-Age=0/, set_cookie)
  end
  
  def test_session_without_plugin
    Aris.routes({
      "example.com" => {
        "/no-session" => {
          get: {
            to: ->(req, res, params) {
              has_session = req.respond_to?(:session)
              res.json({ has_session: has_session })
            }
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    response = adapter.call(
      method: :get,
      path: '/no-session',
      domain: 'example.com'
    )
    
    assert_equal 200, response[:status]
    data = JSON.parse(response[:body].first)
    refute data["has_session"], "Session should not be available without plugin"
  end
end