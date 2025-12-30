# Aris

**A fast, framework-agnostic router for Ruby.**

Aris treats routes as plain data structures instead of code. This design choice makes routing predictable, testable, and roughly 3× faster than comparable frameworks. It works anywhere—Rack apps, CLI tools, background jobs, or custom servers.

## Installation

```ruby
gem 'aris'
```

## Quick Start

Routes are just hashes. Define them once at boot, and Aris compiles them into an optimized lookup structure.

```ruby
Aris.routes({
  "api.example.com": {
    "/users/:id": { 
      get: { to: UserHandler, as: :user }
    }
  }
})
```

Match incoming requests:

```ruby
result = Aris::Router.match(
  domain: "api.example.com",
  method: :get,
  path: "/users/123"
)

result[:handler]  # => UserHandler
result[:params]   # => { id: "123" }
```

Generate paths from named routes:

```ruby
Aris.path("api.example.com", :user, id: 123)
# => "/users/123"
```

That's the core. Everything else builds on these three concepts: define, match, generate.

---

## Core Features

### Multiple HTTP Methods

```ruby
Aris.routes({
  "example.com": {
    "/posts/:id": {
      get: { to: PostShowHandler },
      put: { to: PostUpdateHandler },
      delete: { to: PostDeleteHandler }
    }
  }
})
```

### Wildcards for Catch-All Routes

```ruby
Aris.routes({
  "example.com": {
    "/files/*path": { get: { to: FileHandler } }
  }
})

result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/files/docs/2024/report.pdf"
)
result[:params]  # => { path: "docs/2024/report.pdf" }
```

### Parameter Constraints

Validate parameters at the routing level to fail fast on invalid input.

```ruby
Aris.routes({
  "example.com": {
    "/users/:id": { 
      get: { 
        to: UserHandler,
        constraints: { id: /\A\d{1,8}\z/ }
      }
    }
  }
})
```

### Multi-Domain Routing

Define different routing trees per domain, with wildcard fallback support.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  },
  "admin.example.com": {
    "/": { get: { to: AdminDashboardHandler } }
  },
  "*": {
    "/health": { get: { to: HealthHandler } }
  }
})
```

### Composable Plugins

Plugins execute between routing and handler dispatch. They're just callables that can inspect, modify, or halt the request.

```ruby
class Auth
  def self.call(request, response)
    unless authorized?(request)
      response.status = 401
      response.body = ['Unauthorized']
      return response  # Halts processing
    end
    nil  # Continue to next plugin or handler
  end
end

Aris.routes({
  "api.example.com": {
    use: [CorsHeaders, Auth],  # Applied to all routes
    "/users": { get: { to: UsersHandler } }
  }
})
```

Plugins inherit down the routing tree and can be overridden at any level.

---

### File-Based Route Discovery

Define routes by creating files instead of writing hash definitions. The directory structure maps directly to your routes.

```ruby
# Directory structure:
# app/routes/
#   example.com/
#     users/
#       get.rb          # GET /users
#       _id/
#         get.rb        # GET /users/:id
#   _/
#     health/
#       get.rb          # GET /health on any domain

# app/routes/example.com/users/_id/get.rb
class Handler
  def self.call(request, params)
    { id: params[:id], name: "User #{params[:id]}" }
  end
end

# Boot configuration
Aris.discover_and_define('app/routes')
```

Convention: `domain/path/segments/_param/method.rb`. Use `_` for wildcard domains and parameter names. Each file defines a `Handler` class with a `.call` method.


---

## Use Cases

### Rack Applications

```ruby
# config.ru
Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  }
})

run Aris::Adapters::RackApp.new
```

### CLI Tools

```ruby
# Route commands to handlers
result = Aris::Router.match(
  domain: "cli.internal",
  method: :get,
  path: "/users/#{ARGV[0]}/report"
)

result[:handler].call(result[:params]) if result
```

### Background Jobs

```ruby
class WebhookRouter
  def self.route(event_type, payload)
    result = Aris::Router.match(
      domain: "webhooks.internal",
      method: :post,
      path: "/events/#{event_type}"
    )
    
    result[:handler].call(payload) if result
  end
end
```

### Custom Servers

```ruby
class ServerAdapter
  def handle(native_request)
    result = Aris::Router.match(
      domain: native_request.host,
      method: native_request.method,
      path: native_request.path
    )
    
    return [404, {}, ['Not Found']] unless result
    
    result[:handler].call(native_request, result[:params])
  end
end
```

---

## Error Handling

Define custom handlers for 404s and 500s once, and they'll be used everywhere.

```ruby
Aris.default(
  not_found: ->(req, params) {
    [404, {}, ['{"error": "Not found"}']]
  },
  error: ->(req, exception) {
    ErrorTracker.log(exception)
    [500, {}, ['{"error": "Internal error"}']]
  }
)
```

Trigger these handlers from your code:

```ruby
class UserHandler
  def self.call(request, params)
    user = User.find(params[:id])
    return Aris.not_found(request) unless user
    
    user.to_json
  end
end
```



---

## Performance

Aris compiles routes into a Trie structure at boot time, enabling constant-time lookups regardless of route count. Benchmarks against Roda show 2.5-3.8× faster routing across all scenarios.

```
Root path:            3.1× faster  (570ns vs 1.75μs)
Single parameter:     2.8× faster  (998ns vs 2.78μs)
Two parameters:       3.0× faster  (1.31μs vs 3.89μs)
```

Route matching is O(k) where k is path depth, not route count. Adding 1,000 routes has zero impact on lookup speed—only compilation time increases (3ms for 1,000 routes).

**Why is it fast?**

Routes are data structures, not code. Matching a request is a tree traversal with no method dispatch, no block evaluation, and no runtime metaprogramming. The implementation caches aggressively and minimizes object allocation in the hot path.

---

## Documentation

**[Full Usage Guide](docs/USAGE.md)** - Complete API reference with detailed examples  
**[Adapters Guide](docs/ADAPTERS.md)** - Build on top of aris agnostic interface
**[Architecture](docs/ARCHITECTURE.md)** - Learn all about the design decisions behind Aris
**[Plugin Development](docs/PLUGIN_DEVELOPMENT.md)** - How to build custom middleware  
**[Performance Details](docs/PERFORMANCE.md)** - Benchmarks, profiling, and optimization

---

## FAQ

**Can I use this with Rails or Sinatra?**  
Yes, but it's better suited for new projects or specific use cases like API-only apps, CLI routing, or background job dispatch. For existing apps, Aris works well alongside framework routing rather than replacing it.

**How does this compare to Rack middleware?**  
Aris's plugins run after route matching, so they have access to route parameters and metadata. Rack middleware runs before routing and only sees raw HTTP data. Use both together—Rack for HTTP concerns, Aris plugins for application logic.

**What if I need to add routes at runtime?**  
Calling `Aris.routes` performs a full recompilation (milliseconds for thousands of routes) and isn't thread-safe. Most apps define routes once at boot. For truly dynamic routing, use parameterized routes with dynamic handler logic instead.

**Does it support regex patterns in routes?**  
No, because that would break the Trie optimization. Use wildcard parameters (`*path`) for globbing and constraints for validation. This keeps routing fast while still enforcing requirements.

**How do I handle API versioning?**  
Use domain-based (`v1.api.example.com`) or path-based (`/api/v1/users`) versioning. Both work identically—domain-based gives cleaner separation, path-based keeps everything on one domain.

---

## Contributing

Pull requests welcome. The codebase prioritizes simplicity and performance—every feature should justify its complexity and impact on routing speed.

Run tests: `ruby test/run_all_tests.rb`  
Run benchmarks: `ruby test/bench/vs_roda.rb`

---

## License

MIT

---

## Acknowledgments

Inspired by the pragmatic design of Roda, the performance focus of Aaron Patterson's work, and the elegance of Rack. Thanks to the Ruby community for constantly pushing what's possible.