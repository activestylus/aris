# test/core_test.rb

require_relative "test_helper"
USERS_ROUTE ={"example.com": {"/users": { get: { to: UsersHandler } }}}
HOME_ROUTE = {"example.com": {"/": { get: { to: HomeHandler } }}}
USER_ROUTE = {"example.com": {"/users/:id": { get: { to: UserHandler } }}}
class RouterBasicsTest < Minitest::Test
  def setup
     @router = Aris::Router
  end
  def test_simple_literal_route_matching
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/users")
    assert_equal UsersHandler, result[:handler]
    assert_equal({}, result[:params])
  end
  def test_parameterized_route_matching
    Aris.routes(USER_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/users/123")
    assert_equal UserHandler, result[:handler]
    assert_equal({ id: "123" }, result[:params])
  end
  def test_nested_route_structure
    Aris.routes({"example.com": {"/users": {"/:id": {"/posts": {"/:post_id": { get: { to: UserPostHandler } }}}}}})
    result = @router.match(domain: "example.com",method: :get,path: "/users/42/posts/99")
    assert_equal UserPostHandler, result[:handler]
    assert_equal({ id: "42", post_id: "99" }, result[:params])
  end
  def test_http_method_routing
    Aris.routes({"example.com": {"/users": {get: { to: UsersIndexHandler },post: { to: UsersCreateHandler }}}})
    get_result = @router.match(domain: "example.com", method: :get, path: "/users")
    post_result = @router.match(domain: "example.com", method: :post, path: "/users")
    assert_equal UsersIndexHandler, get_result[:handler]
    assert_equal UsersCreateHandler, post_result[:handler]
  end
  def test_root_path_matching
    Aris.routes(HOME_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/")
    assert_equal HomeHandler, result[:handler]
  end
  def test_no_match_returns_nil
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/posts")
    assert_nil result
  end
  def test_wrong_method_returns_nil
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "example.com", method: :post, path: "/users")
    assert_nil result
  end
  def test_wrong_domain_returns_nil
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "other.com", method: :get, path: "/users")
    assert_nil result
  end
end

class RouterPathNormalizationTest < Minitest::Test
  def setup
    @router = Aris::Router
  end
def test_trailing_slash_stripped
  Aris.configure { |c| c.trailing_slash = :ignore }
  Aris.routes(USERS_ROUTE)
  result = @router.match(domain: "example.com", method: :get, path: "/users/")
  assert_equal UsersHandler, result[:handler]
end
  def test_root_trailing_slash_preserved
    Aris.routes(HOME_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/")
    assert_equal HomeHandler, result[:handler]
  end
  def test_case_insensitive_path_matching
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/USERS")
    assert_equal UsersHandler, result[:handler]
  end
  def test_case_insensitive_domain_matching
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "EXAMPLE.COM", method: :get, path: "/users")
    assert_equal UsersHandler, result[:handler]
  end
def test_uri_decoding_in_path
  Aris.configure { |c| c.trailing_slash = :ignore }
  Aris.routes(USERS_ROUTE)
  # %2F decodes to /, so this becomes /users/ which should match /users
  result = @router.match(domain: "example.com", method: :get, path: "/users%2F")
  assert_equal UsersHandler, result[:handler]
end
  def test_uri_decoding_in_params
    Aris.routes({"example.com": {"/search/:query": { get: { to: SearchHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/search/hello%20world")
    assert_equal SearchHandler, result[:handler]
    assert_equal({ query: "hello world" }, result[:params])
  end
end
class RouterPriorityTest < Minitest::Test
  def setup;@router = Aris::Router;end
  def test_literal_takes_priority_over_param
    Aris.routes({
      "example.com": {
        "/users": {"/new": { get: { to: NewUserHandler } },"/:id": { get: { to: ShowUserHandler } }}
      }
    })
    literal_result = @router.match(domain: "example.com", method: :get, path: "/users/new")
    param_result = @router.match(domain: "example.com", method: :get, path: "/users/123")
    assert_equal NewUserHandler, literal_result[:handler]
    assert_equal ShowUserHandler, param_result[:handler]
    assert_equal({ id: "123" }, param_result[:params])
  end
  def test_param_takes_priority_over_wildcard
    Aris.routes({
      "example.com": {
        "/files": {"/:id": { get: { to: FileHandler } },"/*path": { get: { to: WildcardHandler } }
        }
      }
    })
    param_result = @router.match(domain: "example.com", method: :get, path: "/files/123")
    wildcard_result = @router.match(domain: "example.com", method: :get, path: "/files/a/b/c")
    assert_equal FileHandler, param_result[:handler]
    assert_equal({ id: "123" }, param_result[:params])
    assert_equal WildcardHandler, wildcard_result[:handler]
    assert_equal({ path: "a/b/c" }, wildcard_result[:params])
  end
end

class RouterWildcardTest < Minitest::Test
  def setup
    @router = Aris::Router
  end
  def test_wildcard_matches_multiple_segments
    Aris.routes({"example.com": {"/files/*path": { get: { to: FilesHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/files/docs/readme.md")
    assert_equal FilesHandler, result[:handler]
    assert_equal({ path: "docs/readme.md" }, result[:params])
  end
    def test_wildcard_matches_single_segment
    Aris.routes({"example.com": {"/files/*path": { get: { to: FilesHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/files/readme.md")
    assert_equal FilesHandler, result[:handler]
    assert_equal({ path: "readme.md" }, result[:params])
  end
  def test_named_wildcard
    Aris.routes({"example.com": {"/assets/*file_path": { get: { to: AssetsHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/assets/js/app.js")
    assert_equal AssetsHandler, result[:handler]
    assert_equal({ file_path: "js/app.js" }, result[:params])
  end
  def test_wildcard_in_middle_of_path
    Aris.routes({"example.com": {"/api/*version/users": { get: { to: ApiUsersHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/api/v1/users")
    assert_equal ApiUsersHandler, result[:handler]
    assert_equal({ version: "v1" }, result[:params])
  end
end
class RouterDomainTest < Minitest::Test
  def setup;@router = Aris::Router;end
  def test_multiple_domains
    Aris.routes({
      "example.com": {"/": { get: { to: ExampleHomeHandler } }},
      "admin.example.com": {"/": { get: { to: AdminHomeHandler } }}
    })
    example_result = @router.match(domain: "example.com", method: :get, path: "/")
    admin_result = @router.match(domain: "admin.example.com", method: :get, path: "/")
    assert_equal ExampleHomeHandler, example_result[:handler]
    assert_equal AdminHomeHandler, admin_result[:handler]
  end
  def test_wildcard_domain_fallback
    Aris.routes({
      "example.com": {"users": { get: { to: ExampleUsersHandler } }},
      "*": {"health": { get: { to: HealthHandler } }}
    })
    example_health = @router.match(domain: "example.com", method: :get, path: "/health")
    other_health = @router.match(domain: "other.com", method: :get, path: "/health")
    assert_equal HealthHandler, example_health[:handler]
    assert_equal HealthHandler, other_health[:handler]
  end
  def test_domain_scope_prefix
    Aris.routes({"api.example.com/v1": {"users": { get: { to: ApiV1UsersHandler } }}})
    result = @router.match(domain: "api.example.com/v1", method: :get, path: "/users")
    assert_equal ApiV1UsersHandler, result[:handler]
  end
end
class RouterPipelineTest < Minitest::Test
  def setup;@router = Aris::Router;end
def test_domain_level_use
  Aris.routes({
    "example.com": {use: [:plugin_a, :csrf],"users": { get: { to: UsersHandler } }}
  })
  result = @router.match(domain: "example.com", method: :get, path: "/users")
  assert_equal [TestPluginA, Aris::Plugins::CsrfTokenGenerator, Aris::Plugins::CsrfProtection], result[:use]
end
def test_scope_level_use_override
  Aris.routes({
    "example.com": {use: [:plugin_a],"public": {use: [:plugin_b],"posts": { get: { to: PostsHandler } }}
    }
  })
  result = @router.match(domain: "example.com", method: :get, path: "/public/posts")
  assert_equal [TestPluginA, TestPluginB], result[:use]
end
def test_route_level_use_override
  Aris.routes({
    "example.com": {
      use: [:plugin_a],"users": {get: { to: UsersHandler, as: :users_index, use: [:plugin_b, :plugin_c] }}
    }
  })
  result = @router.match(domain: "example.com", method: :get, path: "/users")
  assert_equal [TestPluginA, TestPluginB, TestPluginC], result[:use]
end

def test_nil_use_means_no_use
  Aris.routes({
    "example.com": {use: [:plugin_a],"health": {use: nil,get: { to: HealthHandler }}}
  })
  result = @router.match(domain: "example.com", method: :get, path: "/health")
  assert_equal [], result[:use]
end
def test_use_inheritance
  Aris.routes({
    "example.com": {use: [:plugin_a, :csrf],"users": {":id": {"posts": { get: { to: UserPostsHandler } }}}}
  })
  result = @router.match(domain: "example.com", method: :get, path: "/users/123/posts")
  assert_equal [TestPluginA, Aris::Plugins::CsrfTokenGenerator, Aris::Plugins::CsrfProtection], result[:use]
end
  def test_single_use_normalized_to_array
    Aris.routes({"example.com": {use: :plugin_a,"users": { get: { to: UsersHandler } }}})
    result = @router.match(domain: "example.com", method: :get, path: "/users")
    assert_equal [TestPluginA], result[:use]
  end
end
class RouterResetTest < Minitest::Test
  def setup;@router = Aris::Router;end
  def test_redefine_removes_old_routes
    Aris.routes(USERS_ROUTE)
    Aris.routes({"example.com": {"posts": { get: { to: PostsHandler } }}})
    users_result = @router.match(domain: "example.com", method: :get, path: "/users")
    posts_result = @router.match(domain: "example.com", method: :get, path: "/posts")
    assert_nil users_result
    assert_equal PostsHandler, posts_result[:handler]
  end
  def test_redefine_removes_old_path_helpers
    Aris.routes({"example.com": { "users": { get: { to: UsersHandler, as: :users_index } } }})
    assert @router.send(:instance_variable_get, :@named_routes).key?(:users_index)
    Aris.routes({"example.com": { "posts": { get: { to: PostsHandler, as: :posts_index } } }})
    refute @router.send(:instance_variable_get, :@named_routes).key?(:users_index), "Old route metadata should be purged."
    assert_equal "/posts", Aris.path("example.com", :posts_index)
  end
end
class RouterComplexScenarioTest < Minitest::Test
  def setup;@router = Aris::Router;end
def test_multi_tenant_cms_example
  Aris.routes({
    "tenant-a.com": {
      use: :public,
      "/": { get: { to: HomeHandler, as: :home } },
      "/posts": {
        get: { to: PostsIndexHandler, as: :posts_index },
        "/:slug": {
          get: { to: PostShowHandler, as: :post_show }
        }
      }
    },
    "admin.platform.com": {
      use: [:plugin_a, :csrf, :admin_auth],
      "/": { get: { to: DashboardHandler, as: :admin_dashboard } },
      "posts": {
        get: { to: AdminPostsIndexHandler, as: :admin_posts_index },
        ":id": {
          get: { to: AdminPostShowHandler, as: :admin_post_show },
          "edit": { get: { to: AdminPostEditHandler, as: :admin_post_edit } }
        }
      }
    },
    "*": {
      use: nil,
      "health": { get: { to: HealthHandler } }
    }
  })
  tenant_result = @router.match(domain: "tenant-a.com",method: :get,path: "posts/hello-world")
  assert_equal PostShowHandler, tenant_result[:handler]
  assert_equal({ slug: "hello-world" }, tenant_result[:params])
  assert_equal [TestPluginPublic], tenant_result[:use]
  admin_result = @router.match(domain: "admin.platform.com",method: :get,path: "posts/123/edit")
  assert_equal AdminPostEditHandler, admin_result[:handler]
  assert_equal({ id: "123" }, admin_result[:params])
  assert_equal [TestPluginA, Aris::Plugins::CsrfTokenGenerator, Aris::Plugins::CsrfProtection, TestPluginAdmin], admin_result[:use]
  health_result = @router.match(domain: "unknown.com",method: :get,path: "health")
  assert_equal HealthHandler, health_result[:handler]
  assert_equal [], health_result[:use]
  Aris.with_domain("tenant-a.com") do
      assert_equal "/posts/my-post", Aris.path(:post_show, slug: "my-post")
  end
  Aris.with_domain("admin.platform.com") do
      assert_equal "/posts/123/edit", Aris.path(:admin_post_edit, id: 123)
  end
end
end

class RouterEdgeCasesTest < Minitest::Test
  def setup;@router = Aris::Router;end
  def test_empty_param_segment
    Aris.routes(USER_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/users/")
    assert_nil result
  end
  def test_multiple_consecutive_slashes_normalized
    Aris.routes(USERS_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "//users")
    assert_nil result
  end
  def test_special_characters_in_literal_segments
    Aris.routes({
      "example.com": {
        "api-v1": { get: { to: ApiHandler } }
      }
    })
    result = @router.match(domain: "example.com", method: :get, path: "/api-v1")
    assert_equal ApiHandler, result[:handler]
  end
  def test_numeric_param_values
    Aris.routes(USER_ROUTE)
    result = @router.match(domain: "example.com", method: :get, path: "/users/123")
    assert_equal "123", result[:params][:id]
    assert_kind_of String, result[:params][:id]
  end
  def test_all_http_methods
    Aris.routes({
      "example.com": {
        "users": {get: { to: GetHandler },post: { to: PostHandler },put: { to: PutHandler },patch: { to: PatchHandler },delete: { to: DeleteHandler }}
      }
    })
    assert_equal GetHandler, @router.match(domain: "example.com", method: :get, path: "/users")[:handler]
    assert_equal PostHandler, @router.match(domain: "example.com", method: :post, path: "/users")[:handler]
    assert_equal PutHandler, @router.match(domain: "example.com", method: :put, path: "/users")[:handler]
    assert_equal PatchHandler, @router.match(domain: "example.com", method: :patch, path: "/users")[:handler]
    assert_equal DeleteHandler, @router.match(domain: "example.com", method: :delete, path: "/users")[:handler]
  end
end
class StandaloneUsageTest < Minitest::Test
  def setup
    # Define a simple route for testing using the public API
    Aris.routes({
      "example.com": {
        "/users": { get: { to: SimpleHandler, as: :users } },
        "/users/:id": { get: { to: UserHandler, as: :user } }
      }
    })
    @router = Aris::Router
  end

  def test_router_in_cli_context
    # Using router in CLI tool or background job
    route = @router.match(domain: "example.com", method: :get, path: "/users")
    
    # Execute business logic directly
    if route
      # Create a simple mock request for standalone context
      mock_request = Object.new
      def mock_request.domain; "example.com"; end
      def mock_request.method; :get; end
      def mock_request.path; "/users"; end
      
      # Call the handler directly (assuming it's a callable class/module)
      handler = route[:handler]
      result = handler.call(mock_request, route[:params])
      
      # Process result for CLI output
      assert_equal "Simple response", result
    else
      flunk "Route should have been found"
    end
  end
  
  def test_custom_adapter_integration
    # Create an instance of the adapter class
    adapter_class = build_custom_framework_adapter
    adapter = adapter_class.new(@router)
    
    mock_request = build_mock_framework_request
    
    response = adapter.handle(mock_request)
    assert response
    assert_equal 200, response[0]
  end
  
  private
  
  def build_custom_framework_adapter
    Class.new do
      def initialize(router)
        @router = router
      end
      
      def handle(request)
        route = @router.match(
          domain: request.domain,
          method: request.method,
          path: request.path
        )
        
        if route
          # Custom framework response handling
          framework_execute(route, request)
        else
          framework_404_response
        end
      end
      
      private
      
      def framework_execute(route, request)
        # Call the actual handler
        handler = route[:handler]
        result = handler.call(request, route[:params])
        
        # Convert to framework response format
        [200, {}, [result.to_s]]
      end
      
      def framework_404_response
        [404, {}, ["Not found in framework"]]
      end
    end
  end
  
  def build_mock_framework_request
    Object.new.tap do |req|
      def req.domain; "example.com"; end
      def req.method; :get; end  
      def req.path; "/users"; end
    end
  end
end

# Simple handler classes for testing
class SimpleHandler
  def self.call(request, params)
    "Simple response"
  end
end

class UserHandler
  def self.call(request, params)
    "User #{params[:id]}"
  end
end