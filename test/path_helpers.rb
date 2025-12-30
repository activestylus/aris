require_relative 'test_helper'

class TestPathURLHelpers < Minitest::Test
  def setup
    # Define a comprehensive routing structure for testing
    Thread.current[:aris_current_domain] = nil
    Aris::Router.default_domain = nil
    Aris::Router.define({
      "example.com": {
        "/users": {
          get: { to: "UsersIndex", as: :users }
        },
        "/users/:id": {
          get: { to: "UsersShow", as: :user },
          delete: { to: "UsersDestroy", as: :user_destroy }
        },
        "/users/:user_id/posts": {
          get: { to: "UserPostsIndex", as: :user_posts }
        },
        "/users/:user_id/posts/:post_id": {
          get: { to: "UserPostsShow", as: :user_post }
        },
        "/files/*path": {
          get: { to: "FilesShow", as: :file }
        }
      },
      "admin.example.com": {
        "/dashboard": {
          get: { to: "AdminDashboard", as: :admin_dashboard }
        },
        "/users": {
          get: { to: "AdminUsers", as: :admin_users }
        },
        "/users/:id": {
          get: { to: "AdminUserShow", as: :admin_user }
        }
      },
      "*": {
        "/health": {
          get: { to: "HealthCheck", as: :health }
        }
      }
    })
  end

  def teardown
    Thread.current[:aris_current_domain] = nil
    Aris::Router.default_domain = nil
  end


  # ==========================================
  # Path Helper Tests
  # ==========================================

  def test_path_single_argument_uses_current_domain
    Thread.current[:aris_current_domain] = "example.com"
    
    assert_equal "/users", Aris.path(:users)
  end

  def test_path_single_argument_uses_default_domain
    Aris::Router.default_domain = "example.com"
    
    assert_equal "/users", Aris.path(:users)
  end

  def test_path_single_argument_raises_without_domain_context
    error = assert_raises(RuntimeError) do
      Aris.path(:users)
    end
    
    assert_match(/No domain context available/, error.message)
  end

  def test_path_two_arguments_uses_explicit_domain
    # No domain context needed when explicit domain provided
    assert_equal "/dashboard", Aris.path("admin.example.com", :admin_dashboard)
  end

  def test_path_with_single_parameter
    Thread.current[:aris_current_domain] = "example.com"
    
    assert_equal "/users/123", Aris.path(:user, id: 123)
  end

  def test_path_with_explicit_domain_and_parameter
    assert_equal "/users/456", Aris.path("admin.example.com", :admin_user, id: 456)
  end

  def test_path_with_multiple_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    assert_equal "/users/42/posts/99", Aris.path(:user_post, user_id: 42, post_id: 99)
  end

  def test_path_with_wildcard_parameter
    Thread.current[:aris_current_domain] = "example.com"
    
    assert_equal "/files/documents/report.pdf", Aris.path(:file, path: "documents/report.pdf")
  end

  def test_path_with_query_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    path = Aris.path(:users, page: 2, per_page: 25)
    assert_equal "/users?page=2&per_page=25", path
  end

  def test_path_missing_required_parameter
    Thread.current[:aris_current_domain] = "example.com"
    
    error = assert_raises(ArgumentError) do
      Aris.path(:user)
    end
    
    assert_match(/Missing required param.*'id'/, error.message)
  end

  def test_path_unknown_route_name
    Thread.current[:aris_current_domain] = "example.com"
    
    
		error = assert_raises(Aris::Router::RouteNotFoundError) do 
	  Aris.path(:nonexistent)
	end
	 
	# FIX: Assert the message is correct.
	assert_match(/Named route :nonexistent not found/, error.message)
  end

  def test_path_wildcard_domain_route
    Thread.current[:aris_current_domain] = "api.example.com"
    
    # Health check is defined on wildcard domain "*"
    assert_equal "/health", Aris.path(:health)
  end

  def test_path_invalid_argument_count
    error = assert_raises(ArgumentError) do
      Aris.path("domain.com", :route, :extra)
    end
    
    assert_match(/Expected 1 or 2 arguments/, error.message)
  end

  # ==========================================
  # URL Helper Tests
  # ==========================================

  def test_url_with_explicit_domain
    url = Aris.url("admin.example.com", :admin_dashboard)
    
    assert_equal "https://admin.example.com/dashboard", url
  end

  def test_url_with_current_domain
    Thread.current[:aris_current_domain] = "example.com"
    
    url = Aris.url(:users)
    
    assert_equal "https://example.com/users", url
  end

  def test_url_with_custom_protocol
    url = Aris.url("admin.example.com", :admin_dashboard, protocol: 'http')
    
    assert_equal "http://admin.example.com/dashboard", url
  end

  def test_url_with_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    url = Aris.url(:user, id: 123)
    
    assert_equal "https://example.com/users/123", url
  end

  def test_url_with_explicit_domain_and_parameters
    url = Aris.url("admin.example.com", :admin_user, id: 456)
    
    assert_equal "https://admin.example.com/users/456", url
  end

  def test_url_with_query_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    url = Aris.url(:users, page: 2)
    
    assert_equal "https://example.com/users?page=2", url
  end

  def test_url_strips_protocol_from_domain
    # If someone accidentally includes protocol in domain
    url = Aris.url("https://admin.example.com", :admin_dashboard)
    
    assert_equal "https://admin.example.com/dashboard", url
  end

  # ==========================================
  # Domain Context Management Tests
  # ==========================================

  def test_thread_local_domain_takes_precedence
    Aris::Router.default_domain = "example.com"
    Thread.current[:aris_current_domain] = "admin.example.com"
    
    path = Aris.path(:admin_dashboard)
    
    assert_equal "/dashboard", path
  end

  def test_default_domain_fallback
    Aris::Router.default_domain = "example.com"
    
    path = Aris.path(:users)
    
    assert_equal "/users", path
  end

  def test_domain_context_isolation_between_threads
    Aris::Router.default_domain = "example.com"
    
    thread1_result = nil
    thread2_result = nil
    
    thread1 = Thread.new do
      Thread.current[:aris_current_domain] = "admin.example.com"
      thread1_result = Aris.path(:admin_dashboard)
    end
    
    thread2 = Thread.new do
      Thread.current[:aris_current_domain] = "example.com"
      thread2_result = Aris.path(:users)
    end
    
    thread1.join
    thread2.join
    
    assert_equal "/dashboard", thread1_result
    assert_equal "/users", thread2_result
  end

  # ==========================================
  # Edge Cases
  # ==========================================

  def test_path_uri_encodes_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    path = Aris.path(:user, id: "user with spaces")
    
    assert_equal "/users/user+with+spaces", path
  end

  def test_path_handles_numeric_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    path = Aris.path(:user, id: 42)
    
    assert_equal "/users/42", path
  end

  def test_url_with_nested_parameters
    Thread.current[:aris_current_domain] = "example.com"
    
    url = Aris.url(:user_post, user_id: 10, post_id: 20, format: 'json')
    
    assert_equal "https://example.com/users/10/posts/20?format=json", url
  end

  def test_case_insensitive_domain_matching
    # Domains are normalized to lowercase
    path = Aris.path("EXAMPLE.COM", :users)
    
    assert_equal "/users", path
  end

  # ==========================================
  # Performance Characteristics Tests
  # ==========================================

  def test_path_performance_single_arg
    Thread.current[:aris_current_domain] = "example.com"
    
    # Should be fast - single thread-local read + direct lookup
    start_time = Time.now
    1000.times { Aris.path(:users) }
    elapsed = Time.now - start_time
    
    # Should complete 1000 calls in under 0.1 seconds on modern hardware
    assert elapsed < 0.1, "Performance regression: took #{elapsed}s for 1000 calls"
  end

  def test_path_performance_two_args
    # Should be fast - no thread-local read needed
    start_time = Time.now
    1000.times { Aris.path("example.com", :users) }
    elapsed = Time.now - start_time
    
    # Should be even faster than single arg
    assert elapsed < 0.1, "Performance regression: took #{elapsed}s for 1000 calls"
  end
end

# Run tests
if __FILE__ == $0
  puts "Running Path and URL Helper Tests..."
  puts "=" * 60
end