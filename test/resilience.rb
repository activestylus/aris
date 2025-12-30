require_relative "test_helper"
# Add these at the top of your test file, after the other constants


# Add these helper methods and classes
def build_env(path, method = 'GET', host = 'example.com')
  {
    'REQUEST_METHOD' => method,
    'PATH_INFO' => path,
    'HTTP_HOST' => host,
    'SERVER_NAME' => host,
    'rack.input' => StringIO.new(''),
    'QUERY_STRING' => ''
  }
end

class SimpleHandler
  def self.call(request, params)
    "Simple response"
  end
end

class SearchHandler
  def self.call(request, params)
    "Search results"
  end
end

# Add large config helper
def large_real_world_config
  {
    "example.com": {
      "/": { get: { to: HomeHandler } },
      "/users": { 
        get: { to: UsersHandler, as: :users },
        post: { to: UsersCreateHandler }
      },
      "/users/:id": { 
        get: { to: UserHandler, as: :user },
        put: { to: UserUpdateHandler },
        delete: { to: UserDeleteHandler }
      },
      "/posts": { 
        get: { to: PostsHandler, as: :posts }
      },
      "/posts/:id": { 
        get: { to: PostHandler, as: :post }
      },
      "/api/v1": {
        "/users": { get: { to: ApiUsersHandler } },
        "/posts": { get: { to: ApiPostsHandler } }
      },
      "/admin": {
        "/dashboard": { get: { to: AdminDashboardHandler } },
        "/users": { get: { to: AdminUsersHandler } }
      }
    },
    "admin.example.com": {
      "/": { get: { to: AdminHomeHandler } },
      "/users": { get: { to: AdminUsersHandler } }
    },
    "*": {
      "/health": { get: { to: HealthHandler } },
      "/status": { get: { to: StatusHandler } }
    }
  }
end

# Now the test classes
class RouterConcurrencyTest < Minitest::Test
  def test_thread_safety_during_route_redefinition
    # Simulate redefining routes while other threads are matching
    Aris.routes(USERS_ROUTE)
    
    redefiner = Thread.new do
      5.times do |i|
        Aris.routes({"example.com": {"/v#{i}": { get: { to: "Handler#{i}" } }}})
        sleep 0.001
      end
    end
    
    matchers = 3.times.map do
      Thread.new do
        50.times do
          # These should not crash even during redefinition
          Aris::Router.match(domain: "example.com", method: :get, path: "/users")
        end
      end
    end
    
    redefiner.join
    matchers.each(&:join)
    # Test passes if no crashes
  end
end

class HandlerExecutionTest < Minitest::Test
  def test_handler_returning_invalid_types
    invalid_handler = ->(req, params) { 12345 } # Not a valid Rack response
    
    Aris.routes({
      "example.com": {
        "/invalid": { get: { to: invalid_handler } }
      }
    })
    
    # Should handle gracefully and convert to valid response
    env = build_env("/invalid")
    status, headers, body = Aris::Adapters::RackApp.new.call(env)
    
    assert_equal 200, status
    assert_equal "12345", body.first
  end
  
  def test_handler_raising_exceptions_during_pipeline
    # Test what happens when pipeline plugins raise exceptions
    exploding_plugin = ->(req, res) { raise "Plugin boom!" }
    
    Aris.routes({
      "example.com": {
        use: [exploding_plugin],
        "/test": { get: { to: SimpleHandler } }
      }
    })
    
    env = build_env("/test")
    status, headers, body = Aris::Adapters::RackApp.new.call(env)
    
    # Should be handled by error system
    assert_equal 500, status
  end
end

class PathGenerationEdgeCasesTest < Minitest::Test
  def test_path_with_special_characters
    Aris.routes({
      "example.com": {
        "/search/:query": { get: { to: SearchHandler, as: :search } }
      }
    })
    
    path = Aris.path("example.com", :search, query: "hello&world=1")
    assert_equal "/search/hello%26world%3D1", path
    
    path = Aris.path("example.com", :search, query: "path/with/slashes")
    assert_equal "/search/path%2Fwith%2Fslashes", path
  end
  
  def test_path_with_array_parameters
    Aris.routes({
      "example.com": {
        "/search": { get: { to: SearchHandler, as: :search } }
      }
    })
    
    path = Aris.path("example.com", :search, tags: ["ruby", "rails"], page: 2)
    # Should handle array parameters in query string
    assert_match /tags=ruby/, path
    assert_match /tags=rails/, path
    assert_match /page=2/, path
  end
end

class RouterConfigurationTest < Minitest::Test
  def test_invalid_route_configuration
    # Test that malformed configurations raise appropriate errors
    assert_raises(ArgumentError) do
      Aris.routes("not a hash")
    end
  end
end

class RouterBenchmarkTest < Minitest::Test
  def test_matching_performance
    require 'benchmark'
    
    Aris.routes(large_real_world_config)
    
    time = Benchmark.realtime do
      1_000.times do  # Reduced from 10,000 to be faster
        Aris::Router.match(domain: "example.com", method: :get, path: "/users/123")
      end
    end
    
    assert time < 0.5, "1,000 matches should take under 0.5 seconds"
  end
end