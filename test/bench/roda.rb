# benchmark/vs_roda.rb
#
# Benchmark Aris::Router against Roda routing performance
#
# Setup:
#   gem install roda
#   ruby benchmark/vs_roda.rb

require 'benchmark/ips'
require 'roda'
require_relative '../../lib/core'

puts "=" * 80
puts "ENJOY::ROUTER VS RODA - ROUTING BENCHMARK"
puts "=" * 80
puts ""

# Mock handlers
class UsersHandler; end
class UserHandler; end
class PostHandler; end
class CommentHandler; end

# ============================================================================
# SETUP: Aris::Router
# ============================================================================

Aris::Router.define({
  "example.com": {
    "/": { get: {to:UsersHandler} },
    "/users": { get: {to:UsersHandler} },
    "/users/:id": { get: {to: UserHandler} },
    "/users/:user_id/posts/:post_id": { get:{to: PostHandler }},
    "/users/:user_id/posts/:post_id/comments/:comment_id": { get: {to: CommentHandler} },
  }
})

# ============================================================================
# SETUP: Roda
# ============================================================================

class RodaApp < Roda
  route do |r|
    # Root
    r.root do
      "ok"
    end
    
    # /users
    r.on "users" do
      # /users/:id
      r.is String do |id|
        r.get do
          "ok"
        end
      end
      
      # /users/:user_id/posts/:post_id
      r.on String, "posts", String do |user_id, post_id|
        r.get do
          "ok"
        end
        
        # /users/:user_id/posts/:post_id/comments/:comment_id
        r.on "comments", String do |comment_id|
          r.get do
            "ok"
          end
        end
      end
      
      # /users (index)
      r.get do
        "ok"
      end
    end
  end
end

# Helper to build Rack env for Roda
def rack_env(method, path)
  {
    'REQUEST_METHOD' => method.to_s.upcase,
    'PATH_INFO' => path,
    'SCRIPT_NAME' => '',
    'SERVER_NAME' => 'example.com',
    'SERVER_PORT' => '80',
    'rack.url_scheme' => 'http'
  }
end

# Warm up both systems
Aris::Router.match(domain: "example.com", method: :get, path: "/users")
RodaApp.call(rack_env(:get, "/users"))

puts "Both systems warmed up and ready\n\n"

# ============================================================================
# BENCHMARK 1: Root Path
# ============================================================================

puts "=" * 80
puts "BENCHMARK 1: Root Path (/)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/"))
  end
  
  x.compare!
end

# ============================================================================
# BENCHMARK 2: Simple Literal Route
# ============================================================================

puts "\n" + "=" * 80
puts "BENCHMARK 2: Simple Literal (/users)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/users")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/users"))
  end
  
  x.compare!
end

# ============================================================================
# BENCHMARK 3: Single Parameter
# ============================================================================

puts "\n" + "=" * 80
puts "BENCHMARK 3: Single Parameter (/users/:id)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/users/123")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/users/123"))
  end
  
  x.compare!
end

# ============================================================================
# BENCHMARK 4: Two Parameters
# ============================================================================

puts "\n" + "=" * 80
puts "BENCHMARK 4: Two Parameters (/users/:user_id/posts/:post_id)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/users/123/posts/456")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/users/123/posts/456"))
  end
  
  x.compare!
end

# ============================================================================
# BENCHMARK 5: Three Parameters (Deep Nesting)
# ============================================================================

puts "\n" + "=" * 80
puts "BENCHMARK 5: Three Parameters (/users/:user_id/posts/:post_id/comments/:comment_id)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/users/123/posts/456/comments/789")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/users/123/posts/456/comments/789"))
  end
  
  x.compare!
end

# ============================================================================
# BENCHMARK 6: 404 (No Route Match)
# ============================================================================

puts "\n" + "=" * 80
puts "BENCHMARK 6: 404 - No Route Match"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("Aris::Router") do
    Aris::Router.match(domain: "example.com", method: :get, path: "/nonexistent")
  end
  
  x.report("Roda") do
    RodaApp.call(rack_env(:get, "/nonexistent"))
  end
  
  x.compare!
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n" + "=" * 80
puts "SUMMARY"
puts "=" * 80
puts ""
puts "NOTE: This benchmark compares ROUTING performance only."
puts ""
puts "Aris::Router measures pure routing (domain → handler lookup)"
puts "Roda measures full request cycle (includes Rack env parsing, middleware, etc.)"
puts ""
puts "For a fair comparison, Aris::Router would need HTTP parsing overhead added."
puts "However, this shows the raw routing engine performance difference."
puts ""
puts "=" * 80