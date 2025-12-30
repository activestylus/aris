# Performance Guide

Aris was built for speed. This guide explains why it's fast, shows benchmark data, and teaches you how to optimize routing in your applications.

---

## Quick Summary

- **2.5-3.8× faster than Roda** across all routing scenarios
- **Sub-microsecond routing** for most requests (500-1,000 nanoseconds)
- **O(k) lookup complexity** where k = path depth, not route count
- **Zero allocation** in the hot path after compilation
- **Thread-safe** for concurrent request processing

Adding 1,000 routes has zero impact on routing speed—only compilation time increases (3ms).

---

## Benchmark Data

All benchmarks run on Ruby 3.3.5 on Apple M1. Your numbers will vary, but relative performance should be similar.

### vs Roda (Head-to-Head)

These benchmarks compare Aris's pure routing against Roda's full request cycle (Rack parsing, middleware, everything). Even with that disadvantage, Aris wins decisively.

```
Benchmark: Root path (/)
  Aris:  1,754,152 req/s  (570 ns/req)
  Roda:     571,119 req/s  (1.75 μs/req)
  Result: 3.07× faster

Benchmark: Simple literal (/users)
  Aris:  1,323,223 req/s  (756 ns/req)
  Roda:     349,001 req/s  (2.87 μs/req)
  Result: 3.79× faster

Benchmark: Single parameter (/users/:id)
  Aris:  1,002,314 req/s  (998 ns/req)
  Roda:     360,031 req/s  (2.78 μs/req)
  Result: 2.78× faster

Benchmark: Two parameters (/users/:user_id/posts/:post_id)
  Aris:    764,682 req/s  (1.31 μs/req)
  Roda:     257,198 req/s  (3.89 μs/req)
  Result: 2.97× faster

Benchmark: Three parameters (/users/:user_id/posts/:post_id/comments/:comment_id)
  Aris:    624,800 req/s  (1.60 μs/req)
  Roda:     250,989 req/s  (3.98 μs/req)
  Result: 2.49× faster

Benchmark: 404 - No route match
  Aris:  1,654,160 req/s  (605 ns/req)
  Roda:     573,374 req/s  (1.74 μs/req)
  Result: 2.88× faster
```

**Important note**: These compare different things. Roda's numbers include the full HTTP processing stack. If you added HTTP parsing overhead to Aris, the gap would narrow. But pure routing-to-routing, Aris is substantially faster.

### Detailed Performance Profile

These benchmarks isolate different aspects of Aris's performance.

**Throughput by route type:**
```
Root path:           1,823,231 req/s  (548 ns/req)
Literal match:       1,316,645 req/s  (760 ns/req)
Single parameter:      984,276 req/s  (1.02 μs/req)
Two parameters:        759,900 req/s  (1.32 μs/req)
Three parameters:      625,294 req/s  (1.60 μs/req)
```

**Priority resolution (same path, different types):**
```
Literal segment:     1,015,040 req/s  (985 ns/req)
Parameter segment:     987,754 req/s  (1.01 μs/req)
Wildcard segment:      475,257 req/s  (2.10 μs/req)
```

Wildcards are slower because they have to try multiple capture lengths. Still fast, but noticeably slower than exact matches.

**Domain resolution:**
```
Exact domain:        1,320,740 req/s  (757 ns/req)
Wildcard domain:     1,142,909 req/s  (875 ns/req)
Fallback to "*":       995,791 req/s  (1.00 μs/req)
```

Domain lookup is fast regardless of type. The fallback is slightly slower because it checks the specific domain first.

**Compilation time (route count → compilation duration):**
```
10 routes:      0.12 ms
100 routes:     0.24 ms
1,000 routes:   3.14 ms
5,000 routes:  15.00 ms
```

Compilation is linear with route count and happens once at boot. Even 5,000 routes compile in 15ms.

**Memory allocation per match:**
```
Literal match:       960 bytes  (18 objects)
Parameterized match: 1,160 bytes (23 objects)
Path helper:         1,520 bytes (26 objects)
```

These allocations are unavoidable—you need to build the params hash and return result objects. But they're minimal.

---

## Why It's Fast

### 1. Compilation, Not Evaluation

Most routers execute code on every request. They evaluate blocks, call methods, check conditions. Aris compiles routes into a Trie structure at boot time. Matching is pure data structure traversal—no method calls, no block evaluation, no conditionals.

```ruby
# Other routers (conceptual):
def match(path)
  routes.each do |route|
    return route.handler if route.pattern.match?(path)  # Code executes
  end
end

# Aris (simplified from actual implementation):
def match(domain, method, path)
  segments = path.split('/').reject(&:empty?)
  node = @tries[domain]
  
  segments.each do |segment|
    # Try literal match first (fastest)
    if node[:literal_children][segment]
      node = node[:literal_children][segment]
    # Fall back to parameter match
    elsif node[:param_child]
      node = node[:param_child][:node]
    else
      return nil  # No match
    end
  end
  
  node[:handlers][method]  # Return handler metadata
end
```

### 2. O(k) Lookup Complexity

Route matching is O(k) where k is the path depth, not the route count. Matching `/users/123/posts/456` performs exactly 4 lookups regardless of whether you have 10 routes or 10,000 routes.

This is why compilation time increases with route count but matching time doesn't. The Trie grows larger, but lookups remain constant depth.

### 3. Structural Sharing

Routes with common prefixes share Trie nodes. If you define:
- `/users/123/posts`
- `/users/123/comments`
- `/users/456/posts`

The Trie only stores `/users/:id` once, then branches at the next segment. Memory usage scales with unique path segments, not total route count.

### 4. Zero Allocation in Hot Path

After compilation, the Trie is immutable. Matching a route doesn't allocate new objects for the Trie structure itself—it just walks existing nodes. The only allocations are for the result hash and params extraction, which you need anyway.

Aris also caches normalized path segments up to a configurable limit (default 1,000), avoiding repeated string operations.

### 5. No Regular Expression Matching in Routing

Route patterns use simple string comparisons for literal segments and single captures for parameters. Constraints use regex, but they're optional and only run after structural matching succeeds.

This means common case routing (literal paths and simple parameters) involves zero regex operations.

---

## Profiling Your Application

The included profiler helps identify bottlenecks in your routing configuration.

```ruby
# benchmark/profiler.rb
require 'aris'
require_relative '../test/profiler'  # Use the profiler from tests

Profiler.new.run_all
```

Output shows timing for compilation, matching, path generation, and memory usage:

```
PROFILING COMPILATION
  tiny: 0.000s (10 routes)
  small: 0.001s (100 routes)
  medium: 0.002s (1,000 routes)
  large: 0.015s (5,000 routes)

PROFILING MATCHING
  root: 0.001s (1,000 iterations)
  literal: 0.001s
  param_1: 0.001s
  param_2: 0.002s
  param_3: 0.002s
  wildcard: 0.007s
  deep_nest: 0.002s
  miss_path: 0.001s
  miss_method: 0.001s
  miss_domain: 0.000s

PROFILING PATH GENERATION
  simple: 0.001s (1,000 iterations)
  param_1: 0.002s
  param_2: 0.002s
  query: 0.003s
  encoded: 0.003s

PROFILING MEMORY
  memory growth: -128KB (after 1,000 matches + 1,000 path generations)
```

If you see any operation taking >0.1s for 1,000 iterations, investigate. Normal operations should be <0.01s per 1,000 iterations.

### Custom Profiling

Add your own routes to the profiler to test realistic scenarios:

```ruby
# In benchmark/profiler.rb
def my_app_config
  {
    "myapp.com": {
      # Your actual routes
    }
  }
end

def profile_my_app
  Aris::Router.define(my_app_config)
  
  # Test your most common paths
  paths = [
    "/users/123",
    "/api/v1/projects/456",
    "/dashboard"
  ]
  
  time = Benchmark.measure do
    10_000.times do
      paths.each do |path|
        Aris::Router.match(domain: "myapp.com", method: :get, path: path)
      end
    end
  end.real
  
  puts "30,000 matches: #{time}s"
  puts "Per match: #{(time / 30_000 * 1_000_000).round(2)}μs"
end

profile_my_app
```

---

## Optimization Techniques

### 1. Minimize Wildcard Routes

Wildcards are 2× slower than exact matches because they try multiple capture lengths. Use them when you need them, but prefer exact segments when possible.

```ruby
# Slower
"/files/*path": { get: { to: FileHandler } }

# Faster (if you know the structure)
"/files/:year/:month/:day/:filename": { get: { to: FileHandler } }
```

### 2. Keep Route Depth Shallow

Route matching is O(k) where k is depth. Prefer flat structures over deep nesting when performance matters.

```ruby
# Slower (depth = 6)
"/api/v1/organizations/:org_id/teams/:team_id/members/:member_id"

# Faster (depth = 4)
"/api/v1/members/:member_id"  # Look up org/team from member
```

This trades routing performance for a database lookup. Usually worth it, but measure your specific case.

### 3. Use Constraints Sparingly

Constraints run regex matches after structural routing succeeds. They're fast, but not as fast as no regex.

```ruby
# Adds regex overhead
constraints: { id: /\A\d{1,8}\z/ }

# No regex overhead
# (validate in handler instead)
```

Only use constraints when you need to fail at routing time. If validation can happen in the handler, do it there.

### 4. Cache Path Generation

Path generation is fast (~1μs), but if you're generating the same path thousands of times per second, cache it.

```ruby
# In a hot loop
users.each do |user|
  url = Aris.url(:user, id: user.id)  # Regenerates every time
end

# Cached
@user_url_template = "/users/%d"
users.each do |user|
  url = @user_url_template % user.id
end
```

This is micro-optimization. Only do it if profiling shows path generation is a bottleneck.

### 5. Use Literal Routes Over Parameters When Possible

Literal segments are slightly faster than parameters because they use hash lookup instead of capture.

```ruby
# If you only have a few known values:
"/users/admin": { get: { to: AdminHandler } }
"/users/moderator": { get: { to: ModeratorHandler } }
"/users/:role": { get: { to: RoleHandler } }

# Better performance for the common cases
```

Again, this is micro-optimization. The difference is 50-100 nanoseconds.

---

## When Performance Matters

**It usually doesn't.** Routing is rarely your bottleneck. Database queries, external API calls, and business logic are almost always slower than routing.

Consider these numbers:
- Routing: 1μs (0.001ms)
- Database query: 10ms (10,000× slower)
- External API call: 100ms (100,000× slower)
- Complex computation: 50ms (50,000× slower)

If your response time is 50ms, routing consumes 0.002% of it. Optimizing routing from 1μs to 0.5μs saves 0.5μs out of 50,000μs. Not worth your time.

**When it does matter:**

1. **Very high request rates** - If you're handling 100,000+ requests per second, routing overhead adds up. At 100K req/s, 1μs routing = 100ms of CPU time per second, or 10% of a core.

2. **Extremely simple handlers** - If your handlers are trivial (return cached data, proxy to another service), routing becomes a larger percentage of total time.

3. **Microservices doing pure routing** - If you have a router service that does nothing but route requests to other services, routing performance is your only job.

4. **Real-time systems** - If you need p99 latency under 5ms, every microsecond counts.

For most applications, focus on handler performance. Make database queries faster, cache aggressively, optimize algorithms. Routing will take care of itself.

---

## Concurrent Performance

Routing is completely thread-safe after compilation. Multiple threads can match routes concurrently with no locks, no synchronization overhead, no contention.

This makes Aris ideal for multi-threaded servers like Puma:

```ruby
# config/puma.rb
workers 4      # Fork 4 processes
threads 5, 5   # 5 threads per worker = 20 concurrent requests

# Each thread routes independently
# No locking, no waiting, no contention
```

Route redefinition (calling `Aris.routes`) is not thread-safe and should only happen at boot or during controlled maintenance windows.

---

## Production Monitoring

Monitor these metrics in production to catch routing-related performance issues:

**Request rate distribution by route:**
```ruby
class MetricsPlugin
  def self.call(request, response)
    route_name = Thread.current[:aris_matched_route_name]
    Metrics.increment("requests.route.#{route_name}")
    nil
  end
end
```

If one route suddenly gets 10× more traffic, you'll see it here before it becomes a problem.

**p50/p95/p99 latency:**
```ruby
class LatencyPlugin
  def self.call(request, response)
    start = Time.now
    response.headers['X-Start-Time'] = start.to_f.to_s
    nil
  end
end

class LatencyReporter
  def self.call(request, response)
    start = response.headers.delete('X-Start-Time')&.to_f
    return nil unless start
    
    duration = Time.now.to_f - start
    route_name = Thread.current[:aris_matched_route_name]
    
    Metrics.histogram("latency.route.#{route_name}", duration)
    nil
  end
end
```

Watch for routes where p99 latency is much higher than p50. Those routes have occasional slowness that needs investigation.

**Memory growth:**
```ruby
# In a monitoring process
def check_memory
  before = memory_usage
  sleep 60
  after = memory_usage
  
  growth = after - before
  alert if growth > threshold
end
```

Routing itself shouldn't cause memory growth. If you see it growing, you likely have a leak in handlers or plugins, not in routing.

---

## Benchmarking Your Own App

Run benchmarks against your actual routes with your actual traffic patterns.

```ruby
# benchmark/my_app.rb
require 'benchmark/ips'
require 'aris'

# Load your routes
require_relative '../config/routes'

# Benchmark your most common paths
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  x.report("dashboard") do
    Aris::Router.match(domain: "app.myapp.com", method: :get, path: "/dashboard")
  end
  
  x.report("user profile") do
    Aris::Router.match(domain: "app.myapp.com", method: :get, path: "/users/12345")
  end
  
  x.report("api endpoint") do
    Aris::Router.match(domain: "api.myapp.com", method: :get, path: "/v1/projects/67890")
  end
  
  x.compare!
end
```

Run this before and after making routing changes to ensure you haven't regressed performance.

---

## The Bottom Line

Aris is fast enough that routing performance should never be your bottleneck. Focus on:

1. **Handler performance** - Database queries, API calls, business logic
2. **Caching** - Don't compute what you can cache
3. **Database optimization** - Indexes, query optimization, connection pooling
4. **Algorithmic improvements** - O(n²) → O(n log n) matters more than routing speed

Routing is solved so you can tackle your actual problems.