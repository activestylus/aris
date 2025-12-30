require_relative "../test_helper"

class Profiler
  def initialize
    @results = {}
    setup_handlers
  end

  def setup_handlers
    @handlers = {}
    %w[Home Users User Posts Post Comments Comment Admin Api Health Metrics Files Assets].each do |name|
      @handlers[name] = Class.new { def self.call(req, params); "ok"; end }
    end
  end

  def profile_compilation
    puts "PROFILING COMPILATION"
    configs = {
      tiny: generate_config(10),
      small: generate_config(100),
      medium: generate_config(1000),
      large: generate_config(5000)
    }
    
    configs.each do |name, config|
      time = Benchmark.measure { Aris::Router.define(config) }.real
      @results["compile_#{name}"] = time
      puts "  #{name}: #{'%.3f' % time}s"
    end
  end

  def profile_matching
    puts "PROFILING MATCHING"
    Aris::Router.define(benchmark_config)
    
    scenarios = {
      root: ["/", {}],
      literal: ["/users", {}],
      param_1: ["/users/123", {id: "123"}],
      param_2: ["/users/123/posts/456", {user_id: "123", post_id: "456"}],
      param_3: ["/users/123/posts/456/comments/789", {user_id: "123", post_id: "456", comment_id: "789"}],
      wildcard: ["/files/docs/readme.md", {path: "docs/readme.md"}],
      deep_nest: ["/a/b/c/d/e/f/g/h/i/j", {}],
      miss_path: ["/nonexistent", nil],
      miss_method: ["/users", nil],
      miss_domain: ["/users", nil]
    }
    
    scenarios.each do |name, (path, expected_params)|
      domain = name == :miss_domain ? "wrong.com" : "example.com"
      method = name == :miss_method ? :post : :get
      
      time = Benchmark.measure { 
        1000.times { Aris::Router.match(domain: domain, method: method, path: path) }
      }.real
      
      @results["match_#{name}"] = time
      puts "  #{name}: #{'%.3f' % time}s"
      
      if expected_params
        result = Aris::Router.match(domain: "example.com", method: :get, path: path)
      end
    end
  end

  def profile_path_generation
    puts "PROFILING PATH GENERATION"
    Aris::Router.define(benchmark_config)
    
    scenarios = {
      simple: [:users, {}],
      param_1: [:user, {id: 123}],
      param_2: [:user_post, {user_id: 123, post_id: 456}],
      query: [:users, {page: 2, per_page: 10}],
      encoded: [:search, {query: "hello&world=1"}]
    }
    
    scenarios.each do |name, (route, params)|
      time = Benchmark.measure { 
        1000.times { Aris.path("example.com", route, **params) }
      }.real
      
      @results["path_#{name}"] = time
      puts "  #{name}: #{'%.3f' % time}s"
    end
  end

  def profile_memory
    puts "PROFILING MEMORY"
    Aris::Router.define(benchmark_config)
    
    mem_before = memory_usage
    1000.times { Aris::Router.match(domain: "example.com", method: :get, path: "/users/123") }
    1000.times { Aris.path("example.com", :user, id: 123) }
    mem_after = memory_usage
    
    @results["memory_growth"] = mem_after - mem_before
    puts "  memory growth: #{@results["memory_growth"]}KB"
  end

  def profile_concurrent
    puts "PROFILING CONCURRENT ACCESS"
    Aris::Router.define(benchmark_config)
    
    time = Benchmark.measure do
      threads = 10.times.map do
        Thread.new do
          100.times do |i|
            Aris::Router.match(domain: "example.com", method: :get, path: "/users/#{i}")
            Aris.path("example.com", :user, id: i)
          end
        end
      end
      threads.each(&:join)
    end.real
    
    @results["concurrent"] = time
    puts "  concurrent: #{'%.3f' % time}s"
  end

  def profile_error_handling
    puts "PROFILING ERROR HANDLING"
    Aris::Router.define(benchmark_config)
    
    time_404 = Benchmark.measure {
      1000.times { Aris::Router.match(domain: "example.com", method: :get, path: "/nonexistent") }
    }.real
    
    time_500 = Benchmark.measure {
      1000.times do
        begin
          Aris.path("wrong.com", :nonexistent_route)
        rescue Aris::Router::RouteNotFoundError
        end
      end
    }.real
    
    @results["error_404"] = time_404
    @results["error_500"] = time_500
    puts "  404: #{'%.3f' % time_404}s, 500: #{'%.3f' % time_500}s"
  end

  def run_all
    puts "=" * 80
    puts "ENJOY::ROUTER COMPREHENSIVE PROFILER"
    puts "=" * 80
    
    profile_compilation
    profile_matching
    profile_path_generation
    profile_memory
    profile_concurrent
    profile_error_handling
    
    report_bottlenecks
  end

  private

  def generate_config(size)
    config = { "example.com": {} }
    domain_config = config[:"example.com"]
    
    size.times do |i|
      domain_config["/route#{i}"] = { get: { to: @handlers["Home"], as: :"route#{i}" } }
    end
    
    config
  end

  def benchmark_config
    {
      "example.com": {
        use: [:web, :csrf],
        "/": { get: { to: @handlers["Home"], as: :home } },
        "/users": { 
          get: { to: @handlers["Users"], as: :users },
          post: { to: @handlers["Users"] }
        },
        "/users/:id": { 
          get: { to: @handlers["User"], as: :user },
          put: { to: @handlers["User"] },
          delete: { to: @handlers["User"] }
        },
        "/users/:user_id/posts/:post_id": { 
          get: { to: @handlers["Post"], as: :user_post }
        },
        "/users/:user_id/posts/:post_id/comments/:comment_id": { 
          get: { to: @handlers["Comment"], as: :comment }
        },
        "/posts": { get: { to: @handlers["Posts"], as: :posts } },
        "/posts/:id": { get: { to: @handlers["Post"], as: :post } },
        "/search/:query": { get: { to: @handlers["Posts"], as: :search } },
        "/files/*path": { get: { to: @handlers["Files"], as: :file } },
        "/a/b/c/d/e/f/g/h/i/j": { get: { to: @handlers["Home"] } }
      },
      "admin.example.com": {
        use: [:admin_auth],
        "/": { get: { to: @handlers["Admin"], as: :admin } },
        "/users": { get: { to: @handlers["Users"], as: :admin_users } }
      },
      "api.example.com": {
        use: [:api],
        "/v1": {
          "/users": { get: { to: @handlers["Users"], as: :api_users } }
        }
      },
      "*": {
        "/health": { get: { to: @handlers["Health"], as: :health } },
        "/metrics": { get: { to: @handlers["Metrics"], as: :metrics } }
      }
    }
  end

  def memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i
  end

  def report_bottlenecks
    puts "=" * 80
    puts "BOTTLENECK ANALYSIS"
    puts "=" * 80
    
    slowest = @results.max_by { |k, v| v }
    fastest = @results.min_by { |k, v| v }
    
    puts "Slowest: #{slowest[0]} - #{'%.3f' % slowest[1]}s"
    puts "Fastest: #{fastest[0]} - #{'%.3f' % fastest[1]}s"
    
    bottlenecks = @results.select { |k, v| v > 0.1 }
    if bottlenecks.any?
      puts "Potential bottlenecks (>0.1s):"
      bottlenecks.each { |k, v| puts "  #{k}: #{'%.3f' % v}s" }
    else
      puts "No significant bottlenecks detected"
    end
  end
end

Profiler.new.run_all if __FILE__ == $0