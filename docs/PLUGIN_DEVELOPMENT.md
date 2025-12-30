# Plugin Development Guide

This guide covers building reusable plugins for Aris. It assumes you've read the plugin section in the main usage guide and understand the basics of how plugins work.

---

## Plugin Registry

Plugins are registered with a symbol name for clean routing configuration. The registry resolves symbols to one or more plugin classes.

```ruby
# Single plugin
Aris.register_plugin(:json, plugin_class: Json)

# Multi-class plugin (like CSRF with generator + protection)
Aris.register_plugin(:csrf, 
  generator: CsrfTokenGenerator,
  protection: CsrfProtection
)

# Usage in routes - symbols resolve to classes
Aris.routes({
  "api.example.com": {
    use: [:csrf, :json],  # Expands to all plugin classes
    "/users": { get: { to: UsersHandler } }
  }
})
```

**Important:** All symbols in `use:` arrays must be registered plugins. Unregistered symbols will raise `ArgumentError: Unknown plugin :symbol_name`.

---

## Design Principles

**Plugins should do one thing.** Don't build a plugin that handles authentication AND rate limiting AND logging. Build three plugins and compose them.

**Plugins should be stateless.** All state should live in the request, response, or explicitly passed dependencies. No class variables, no globals.

**Plugins should fail explicitly.** If something goes wrong, halt with a clear error response. Don't let bad requests reach handlers.

**Plugins should be fast.** They run on every request. Profile them. Optimize them. Cache aggressively.

---

## State Management: The Mutability Contract

Aris uses a strict contract to manage data flow: **Request data is immutable; Response state is mutable.**

| Object | State | How to Share/Access Data |
|:---|:---|:---|
| **`request` (Aris::Request)** | **Immutable** | Primary source of incoming data. Accessors: `request.method`, `request.path`, `request.headers`, `request.params`. |
| **`response` (Aris::Response)** | **Mutable** | Used to signal **HALT** (by returning the object) or **mutate final output** (`response.headers`, `response.status`, `response.body`). |

### Request Object Extension (The Cleanest Pattern)

For data that is part of the application context (like the current authenticated user), the cleanest approach is to extend the request object using instance variables.

```ruby
class AuthPlugin
  def self.call(request, response)
    token = request.headers['HTTP_AUTHORIZATION']
    user = authenticate(token)
    
    return unauthorized_response(response) unless user
    
    # Attach user to request for handlers (low allocation)
    request.instance_variable_set(:@current_user, user)
    nil
  end
  
  def self.authenticate(token)
    # Your auth logic
  end
  
  def self.unauthorized_response(response)
    response.status = 401
    response.body = ['Unauthorized']
    response
  end
end

# In your handler (accesses the injected user)
class UserHandler
  def self.call(request, params)
    # The handler must know the convention (@current_user)
    current_user = request.instance_variable_get(:@current_user)
    # Use current_user
  end
end
```

This pattern is clean but requires handlers to know about the plugin's conventions. Document what instance variables your plugin sets.

### Response Headers as Ephemeral State

The simplest pattern for sharing simple, string-based data (like timers, IDs, or debugging flags) is response headers.

```ruby
class RequestTimer
  def self.call(request, response)
    # Store start time for duration calculation by a later plugin
    response.headers['X-Request-Start'] = Time.now.to_f.to_s
    nil
  end
end

class ResponseTimer
  def self.call(request, response)
    if start = response.headers['X-Request-Start']
      duration = Time.now.to_f - start.to_f
      response.headers['X-Duration-Ms'] = (duration * 1000).round(2).to_s
    end
    nil
  end
end
```

This works well for small amounts of data. Headers are visible in the response, so don't put sensitive data here unless you clean it up later.

### Thread-Local Storage (Use Sparingly)

For data that needs to be accessible deep in the call stack without passing it through every method, use thread-local storage.

```ruby
class RequestContext
  def self.call(request, response)
    Thread.current[:request_id] = SecureRandom.uuid
    Thread.current[:current_user] = authenticate(request)
    nil
  ensure
    # CRITICAL: Always clean up thread-local state
    Thread.current[:request_id] = nil
    Thread.current[:current_user] = nil
  end
end

# Accessible anywhere in the request
class DeepHandler
  def self.call(request, params)
    request_id = Thread.current[:request_id]
    Logger.info("Request #{request_id}: Processing user #{params[:id]}")
  end
end
```

**Warning:** Always clean up thread-local state in an `ensure` block. Failing to do so causes state to leak between requests in threaded servers, leading to critical security and concurrency bugs.

---

## Common Patterns

### Authentication

```ruby
class BearerAuth
  def self.call(request, response)
    auth_header = request.headers['HTTP_AUTHORIZATION']
    
    unless auth_header&.start_with?('Bearer ')
      return halt_with(response, 401, 'Missing or invalid Authorization header')
    end
    
    token = auth_header.sub('Bearer ', '')
    user = User.find_by(api_token: token)
    
    unless user
      return halt_with(response, 401, 'Invalid token')
    end
    
    request.instance_variable_set(:@current_user, user)
    nil
  end
  
  private
  
  def self.halt_with(response, status, message)
    response.status = status
    response.headers['content-type'] = 'application/json'
    # Ensure body is correctly arrayed as per Rack standard
    response.body = [%({"error": "#{message}"})]
    response
  end
end
```

### Rate Limiting

```ruby
class RateLimiter
  LIMIT = 100
  WINDOW = 60 # seconds
  
  def self.call(request, response)
    key = rate_limit_key(request)
    count = increment_count(key)
    
    response.headers['X-RateLimit-Limit'] = LIMIT.to_s
    response.headers['X-RateLimit-Remaining'] = [LIMIT - count, 0].max.to_s
    
    if count > LIMIT
      response.status = 429
      response.headers['Retry-After'] = WINDOW.to_s
      response.body = ['Rate limit exceeded']
      return response
    end
    
    nil
  end
  
  private
  
  def self.rate_limit_key(request)
    # Use API key, IP, or user ID
    request.headers['HTTP_X_API_KEY'] || request.headers['REMOTE_ADDR']
  end
  
  def self.increment_count(key)
    # Implement with Redis
    REDIS.multi do
      REDIS.incr("rate_limit:#{key}")
      REDIS.expire("rate_limit:#{key}", WINDOW)
    end.first
  end
end
```

### CORS Headers

```ruby
class Cors
  ALLOWED_ORIGINS = ['https://example.com', 'https://app.example.com']
  
  def self.call(request, response)
    origin = request.headers['HTTP_ORIGIN']
    
    if ALLOWED_ORIGINS.include?(origin)
      response.headers['Access-Control-Allow-Origin'] = origin
      response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE'
      response.headers['Access-Control-Allow-Headers'] = 'content-type, Authorization'
      response.headers['Access-Control-Max-Age'] = '86400'
    end
    
    # Handle preflight requests
    if request.method == 'OPTIONS'
      response.status = 204
      response.body = []
      return response
    end
    
    nil
  end
end
```

### Request Logging

```ruby
class RequestLogger
  def self.call(request, response)
    start_time = Time.now
    
    # Store start time for later
    response.headers['X-Request-Start'] = start_time.to_f.to_s
    
    nil
  end
end

class ResponseLogger
  def self.call(request, response)
    start_time_str = response.headers.delete('X-Request-Start')
    return nil unless start_time_str
    
    duration = Time.now.to_f - start_time_str.to_f
    
    Logger.info({
      method: request.method,
      path: request.path,
      status: response.status,
      duration_ms: (duration * 1000).round(2)
    }.to_json)
    
    nil
  end
end

# Use both together
Aris.routes({
  "api.example.com": {
    use: [RequestLogger, ResponseLogger],
    # routes...
  }
})
```

### Caching

```ruby
class CachePlugin
  def self.call(request, response)
    # Only cache GET requests
    return nil unless request.method == 'GET'
    
    cache_key = "response:#{request.domain}:#{request.path}"
    
    if cached = REDIS.get(cache_key)
      response.status = 200
      response.headers['content-type'] = 'application/json'
      response.headers['X-Cache'] = 'HIT'
      response.body = [cached]
      return response
    end
    
    # Mark as cache miss for potential post-handler caching
    response.headers['X-Cache'] = 'MISS'
    nil
  end
end
```

---

## Plugin Composition

Plugins execute in order. Use this to build pipelines where later plugins depend on earlier ones.

```ruby
Aris.routes({
  "api.example.com": {
    use: [
      CorsHeaders,      # Set headers first
      BearerAuth,       # Auth before rate limiting
      RateLimiter,      # Rate limit authenticated users
      RequestLogger     # Log after auth passes
    ],
    # routes...
  }
})
```

Order matters. Expensive operations should come after cheap validation. If auth fails, you shouldn't hit the rate limiter or logger.

**All items in `use:` must be callable.** Use registered plugin symbols (`:csrf`, `:rate_limit`) or direct class references (`MyPlugin`). The router resolves symbols to classes at compile time, so there's no runtime overhead.

### Conditional Execution

Sometimes plugins need to behave differently based on context.

```ruby
class ConditionalAuth
  def self.call(request, response)
    # Skip auth for public endpoints
    return nil if public_path?(request.path)
    
    # Run auth for everything else
    auth_header = request.headers['HTTP_AUTHORIZATION']
    return halt_unauthorized(response) unless valid_token?(auth_header)
    
    nil
  end
  
  private
  
  def self.public_path?(path)
    ['/health', '/version', '/public/status'].include?(path)
  end
end
```

Better yet, use route-level `use: nil` to clear inherited plugins entirely.

```ruby
Aris.routes({
  "api.example.com": {
    use: [Auth, RateLimiter],
    
    "/users": { get: { to: UsersHandler } },
    
    "/health": {
      use: nil,  # Clear all plugins
      get: { to: HealthHandler }
    }
  }
})
```

---

## Testing Plugins

Test plugins in isolation with mock request and response objects.

```ruby
require 'minitest/autorun'

class AuthPluginTest < Minitest::Test
  def test_valid_token_continues
    # Mocking only the necessary methods on the request object
    request = mock_request(headers: {'HTTP_AUTHORIZATION' => 'Bearer valid-token'})
    response = Aris::Response.new
    
    result = BearerAuth.call(request, response)
    
    assert_nil result, "Should return nil to continue processing"
    assert_equal 200, response.status
  end
  
  def test_invalid_token_halts
    request = mock_request(headers: {'HTTP_AUTHORIZATION' => 'Bearer invalid'})
    response = Aris::Response.new
    
    result = BearerAuth.call(request, response)
    
    assert_equal response, result, "Should return response object to halt"
    assert_equal 401, response.status
    assert_match /Invalid token/, response.body.first
  end
  
  def test_missing_token_halts
    request = mock_request(headers: {})
    response = Aris::Response.new
    
    result = BearerAuth.call(request, response)
    
    assert_equal 401, response.status
  end
  
  private
  
  def mock_request(headers: {})
    # Minimal mocking utility
    req = Object.new
    req.define_singleton_method(:headers) { headers }
    req.define_singleton_method(:method) { 'GET' }
    req
  end
end
```

For integration tests, test the full plugin chain with real routes.

```ruby
class PluginIntegrationTest < Minitest::Test
  def setup
    Aris.routes({
      "api.example.com": {
        use: [BearerAuth, RateLimiter],
        "/users": { get: { to: UsersHandler } }
      }
    })
    
    @app = Aris::Adapters::RackApp.new
  end
  
  def test_authenticated_request_succeeds
    env = build_env('/users', 'GET', 'Bearer valid-token')
    status, headers, body = @app.call(env)
    
    assert_equal 200, status
  end
  
  def test_unauthenticated_request_fails
    env = build_env('/users', 'GET', nil)
    status, headers, body = @app.call(env)
    
    assert_equal 401, status
  end
  
  private
  
  def build_env(path, method, auth)
    {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'HTTP_HOST' => 'api.example.com',
      'HTTP_AUTHORIZATION' => auth,
      'rack.input' => StringIO.new('')
    }
  end
end
```

---

## Performance Considerations

Plugins run on every request. Profile them and optimize aggressively.

### Avoid N+1 Queries

```ruby
# Bad - queries database on every request
class BadAuth
  def self.call(request, response)
    token = request.headers['HTTP_AUTHORIZATION']
    user = User.find_by(api_token: token)  # DB query
    # ...
  end
end

# Better - cache user lookups in a shared CACHE layer
class BetterAuth
  def self.call(request, response)
    token = request.headers['HTTP_AUTHORIZATION']
    user = cached_user_lookup(token)  # Check cache before DB
    # ...
  end
  
  def self.cached_user_lookup(token)
    cache_key = "user:token:#{token}"
    CACHE.fetch(cache_key, expires_in: 300) do
      User.find_by(api_token: token)
    end
  end
end
```

### Minimize Object Allocation

```ruby
# Bad - creates new strings on every request
class BadLogger
  def self.call(request, response)
    Logger.info("Request: " + request.method + " " + request.path)
    nil
  end
end

# Better - use string interpolation (single allocation)
class BetterLogger
  def self.call(request, response)
    Logger.info("Request: #{request.method} #{request.path}")
    nil
  end
end

# Best - reuse format string
class BestLogger
  FORMAT = "Request: %s %s"
  
  def self.call(request, response)
    Logger.info(FORMAT % [request.method, request.path])
    nil
  end
end
```

### Early Exit

Check the cheapest conditions first and exit early when possible.

```ruby
class OptimizedAuth
  def self.call(request, response)
    # 1. Check for header existence (cheapest check)
    auth_header = request.headers['HTTP_AUTHORIZATION']
    return halt_unauthorized(response) unless auth_header
    
    # 2. Check prefix (cheap string comparison)
    return halt_unauthorized(response) unless auth_header.start_with?('Bearer ')
    
    # 3. Check token length (cheap computation)
    token = auth_header.sub('Bearer ', '')
    return halt_unauthorized(response) unless token.length > 20
    
    # 4. Database lookup (most expensive check, performed last)
    user = User.find_by(api_token: token)
    return halt_unauthorized(response) unless user
    
    request.instance_variable_set(:@current_user, user)
    nil
  end
end
```

---

## Distributing Plugins

If you're building plugins for others to use, follow these conventions.

### Structure

```ruby
# lib/aris/plugins/my_plugin.rb
module Aris
  module Plugins
    class MyPlugin
      def self.call(request, response)
        # Implementation
      end
    end
  end
end
```

### Configuration

Make plugins configurable without using globals.

```ruby
# Bad - uses class variables
class Configurable
  @@api_key = nil
  
  def self.api_key=(key)
    @@api_key = key
  end
  
  def self.call(request, response)
    # Uses @@api_key
  end
end

# Better - use initialization
class Configurable
  def initialize(api_key:)
    @api_key = api_key
  end
  
  def call(request, response)
    # Uses @api_key
  end
end

# Usage
Aris.routes({
  "api.example.com": {
    use: [Configurable.new(api_key: ENV['API_KEY'])],
    # routes...
  }
})
```

### Documentation

Document what your plugin does, what it requires, and what side effects it has.

```ruby
# Authenticates requests using bearer tokens from the Authorization header.
#
# Requirements:
# - User model with `api_token` column
# - Authorization header in format: "Bearer <token>"
#
# Side effects:
# - Sets @current_user instance variable on request object
# - Returns 401 response for missing/invalid tokens
#
# Example:
#   Aris.routes({
#     "api.example.com": {
#       use: [BearerAuth],
#       "/users": { get: { to: UsersHandler } }
#     }
#   })
class BearerAuth
  # ...
end
```

When distributing plugins, users must register them before using them in routes. Include registration instructions in your documentation:

```ruby
# Installation (in user's code)
require 'aris/plugins/my_plugin'
Aris.register_plugin(:my_plugin, plugin_class: MyPlugin)
```
---

## Common Pitfalls

**Using class variables for state** - They leak between requests. Use the request/response objects or thread-local storage.

**Forgetting to return nil** - If you don't explicitly return nil or the response, Ruby returns the last expression, which can cause unexpected halts.

**Expensive operations before auth** - Always authenticate before doing expensive work like database queries or external API calls.

**Not cleaning up thread-local state** - Always use ensure blocks when setting thread-local variables.

**Halting without setting response body** - Always set status, headers, and body when halting. Empty bodies can cause issues with some clients.

**Modifying request.params** - The params hash comes from routing. Don't mutate it. If you need to add data, use instance variables on the request object.

---

That covers the essential patterns for building robust, performant plugins. The key insight is that plugins are just functions with a contract—keep them simple, stateless, and fast, and they'll serve you well.