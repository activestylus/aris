require_relative "test_helper"

class RouterConstraintTest < Minitest::Test
  def setup
    @router = Aris::Router
    Aris.routes({
      "example.com": {
        "/users/:id": { 
          get: { 
            to: "Users::ShowHandler", 
            as: :user_show,
            constraints: { id: /\A\d+\z/ }
          }
        },
        "/users/new": {
          get: { 
            to: "Users::NewHandler", 
            as: :user_new
          }
        },
        "/pages/:slug": { 
          get: { 
            to: "Pages::ShowHandler", 
            as: :page_show
          } 
        }
      }
    })
  end

  def test_01_parameter_passes_constraint
    result = @router.match(domain: "example.com", method: :get, path: "/users/123")
    
    assert result
    assert_equal "Users::ShowHandler", result[:handler]
    assert_equal({ id: "123" }, result[:params])
  end

  def test_02_parameter_passes_named_route_lookup
    result = @router.match(domain: "example.com", method: :get, path: "/users/999")
    
    assert_equal :user_show, result[:name]
  end

  def test_03_parameter_fails_constraint_check
    result = @router.match(domain: "example.com", method: :get, path: "/users/abc")
    assert_nil result, "Request should fail constraint check and return nil"
  end

  def test_04_literal_route_takes_priority_over_constrained_route
    result = @router.match(domain: "example.com", method: :get, path: "/users/new")
    assert_equal "Users::NewHandler", result[:handler], "Literal match must win before constraint check is finalized"
    assert_equal({}, result[:params], "Literal routes should return empty params hash")
  end

  def test_05_failed_constrained_route_does_not_block_other_routes
    result = @router.match(domain: "example.com", method: :get, path: "/pages/my-article")
    assert_equal "Pages::ShowHandler", result[:handler]
    assert_equal({ slug: "my-article" }, result[:params])
  end
end
