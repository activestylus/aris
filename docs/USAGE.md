# Aris Router - Complete Usage Guide

This guide covers everything you need to know about using Aris, from basic routing to advanced patterns. We will start with fundamental concepts and build up to more sophisticated use cases, explaining the reasoning behind each design decision along the way.

---

## Table of Contents

1. [Core Philosophy](#core-philosophy)
2. [Defining Routes](#defining-routes)
3. [Route Matching](#route-matching)
4. [Path and URL Generation](#path-and-url-generation)
5. [HTTP Methods](#http-methods)
6. [Parameters and Wildcards](#parameters-and-wildcards)
7. [AutoDiscovery Routes](#auto-discovery)
8. [Constraints](#constraints)
9. [Multi-Domain Routing](#multi-domain-routing)
10. [The Plugin System](#the-plugin-system)
11. [Error Handling](#error-handling)
12. [Rack Integration](#rack-integration)
13. [Standalone Usage](#standalone-usage)
14. [Advanced Patterns](#advanced-patterns)
15. [Complete API Reference](#complete-api-reference)

---

## Core Philosophy

Before we dive into the specifics, it helps to understand what makes Aris different from other routing libraries you may have used.

### Routes as Data

Most Ruby routers use domain-specific languages that execute code during route definition. When you write something like `get '/users/:id', to: 'users#show'` in Rails, you are actually calling methods that build internal data structures at runtime. This feels natural and reads well, but it introduces a layer of abstraction between your intent and the actual routing logic.

Aris takes a different approach. Routes are defined as plain Ruby hashes—literal data structures that describe the shape of your application's URL space. This choice has several implications that ripple through the entire design.

When routes are data, they become serializable. You can load them from YAML files, generate them from database records, or build them programmatically using any Ruby code you want. They can be inspected, transformed, and tested like any other data structure. There is no magic happening behind the scenes, no implicit state being managed, no hidden method calls evaluating blocks.

This data-first design also enables aggressive optimization. Since Aris knows the complete routing table upfront, it can compile it into an optimized Trie structure at boot time. Every possible path through your application is analyzed once, and the resulting lookup structure is frozen for the lifetime of the process. This is why Aris can route requests in under a microsecond—the hard work is done before the first request arrives.

### Framework Agnosticism

The second core principle is complete independence from any web framework. Aris exposes a simple functional interface: you give it a domain, method, and path, and it returns routing metadata. That is it. No assumptions about Rack, no Rails conventions, no Sinatra DSL patterns.

This agnosticism is not just philosophical—it opens up use cases that are awkward or impossible with framework-coupled routers. You can use Aris to route commands in a CLI application, dispatch events in a background job system, or build a custom HTTP server that bypasses Ruby's standard library entirely. The routing logic is yours to use however you need.

### Explicit Over Implicit

The third principle is explicitness. Aris does not try to be clever or infer your intentions. Every route requires an explicit domain. Every handler must be explicitly specified. Every plugin must be explicitly listed.

This can feel verbose at first, especially if you are coming from frameworks that do a lot of work behind the scenes. But explicitness has a payoff: when something goes wrong, you know exactly where to look. There are no hidden middleware chains, no automatic route generation, no framework magic that might or might not apply in your specific situation.

With these principles in mind, let us start building.

---

## Defining Routes

Route definition in Aris happens through a single method: `Aris.routes`. This method takes a configuration hash and performs a complete reset and recompilation of the routing table. Let us start with the simplest possible route definition and build up from there.

### Your First Route

```ruby
Aris.routes({
  "example.com": {
    "/": { 
      get: { to: HomeHandler } 
    }
  }
})
```

This defines a single route on `example.com` that responds to GET requests at the root path. The handler is `HomeHandler`, which should be a callable object (we will cover what that means shortly).

Notice the structure here. The outermost hash keys are domains. Each domain contains a hash of path segments. Each path segment contains HTTP method definitions. Each method definition specifies a handler and optional metadata.

This nesting might feel unusual at first, but it has a purpose. The structure of the hash mirrors the conceptual structure of your routing tree. Routes are organized by domain, then by path, then by method. This organization makes it easy to see which routes belong to which parts of your application.

### Adding Named Routes

Most applications need to generate URLs from route definitions. This is where named routes come in.

```ruby
Aris.routes({
  "example.com": {
    "/": { 
      get: { to: HomeHandler, as: :home } 
    },
    "/about": { 
      get: { to: AboutHandler, as: :about } 
    }
  }
})
```

The `as:` option gives the route a name that you can use later for path generation. Route names must be unique across your entire routing table—if you try to define two routes with the same name, Aris will raise an error during compilation.

This uniqueness constraint is intentional. Named routes create a stable API for URL generation throughout your application. If the same name could refer to different routes depending on context, you would lose that stability and introduce potential bugs.

### Nested Path Segments

Real applications need more than flat route tables. Paths are hierarchical, and your route definitions should reflect that hierarchy.

```ruby
Aris.routes({
  "example.com": {
    "/users": {
      get: { to: UsersIndexHandler, as: :users },
      
      "/:id": {
        get: { to: UserShowHandler, as: :user },
        
        "/posts": {
          get: { to: UserPostsHandler, as: :user_posts }
        }
      }
    }
  }
})
```

This defines three routes:
- `GET /users` - handled by `UsersIndexHandler`
- `GET /users/:id` - handled by `UserShowHandler`
- `GET /users/:id/posts` - handled by `UserPostsHandler`

The nesting structure makes it clear that these routes are related. They all live under the `/users` namespace, and you can see at a glance how they connect to each other. If you later need to add authentication to all user routes, you know exactly where to add the plugin (we will cover plugins soon).

Notice that path segments can be literal strings like `/posts` or parameterized patterns like `/:id`. When a segment starts with a colon, Aris treats it as a parameter that will capture whatever value appears in that position in the incoming request.

### Multiple Domains

Modern applications often serve multiple domains. Perhaps you have a public site, an admin dashboard, and an API, each on its own subdomain or domain entirely.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: PublicHomeHandler } }
  },
  
  "admin.example.com": {
    "/": { get: { to: AdminDashboardHandler } }
  },
  
  "api.example.com": {
    "/v1": {
      "/users": { get: { to: ApiUsersHandler } }
    }
  }
})
```

Each domain gets its own routing tree. These trees are completely independent—you can have a `/users` route on both `example.com` and `api.example.com`, and they will not conflict. The domain is always part of the routing decision, so Aris knows exactly which tree to search.

This domain-level isolation is powerful for multi-tenant applications. Each tenant can have its own domain with its own routing rules, all managed in a single configuration.

### The Wildcard Domain

Sometimes you need routes that work on any domain. Health checks, status endpoints, and other infrastructure concerns often fall into this category.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  },
  
  "*": {
    "/health": { get: { to: HealthCheckHandler } },
    "/metrics": { get: { to: MetricsHandler } }
  }
})
```

The special domain `"*"` acts as a fallback. When a request comes in, Aris first checks if there is a specific domain match. If not, it falls back to the wildcard domain routes.

This fallback behavior is important to understand. If you define a `/health` route on both `example.com` and the wildcard domain, a request to `example.com/health` will match the specific domain route, not the wildcard. Specific domains always win.

---

## Route Matching

Once routes are defined, you need to match incoming requests against them. This is where the routing engine shows its speed.

### Basic Matching

The core matching method is `Aris::Router.match`. It takes three required parameters and returns either a hash of routing metadata or nil if no route matches.

```ruby
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/123"
)

if result
  # Route was found
  handler = result[:handler]    # The handler to call
  params = result[:params]      # Extracted parameters: { id: "123" }
  name = result[:name]          # The route name (if it has one)
  plugins = result[:use]        # Plugins to execute (more on this later)
else
  # No route matched
end
```

The returned hash contains everything you need to handle the request. The handler is exactly what you specified in your route definition. The params hash contains any values extracted from parameterized path segments. The name is the route's `as:` value if you provided one. The plugins array contains any middleware that should execute before the handler.

### Parameter Extraction

When a route contains parameterized segments (those starting with `:`), Aris extracts the corresponding values from the request path and returns them in the params hash.

```ruby
Aris.routes({
  "example.com": {
    "/posts/:year/:month/:slug": {
      get: { to: PostHandler }
    }
  }
})

result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/posts/2024/03/hello-world"
)

result[:params]  
# => { year: "2024", month: "03", slug: "hello-world" }
```

All parameter values are strings. Aris does not attempt to convert them to integers, dates, or any other type. This is intentional—type coercion belongs in your application layer where you have context about what the values mean and how they should be validated.

### Path Normalization

Before matching, Aris normalizes the incoming path to ensure consistent behavior. Understanding this normalization is important for writing reliable routes.

First, trailing slashes are stripped from all paths except the root. This means `/users` and `/users/` are treated identically. You do not need to define separate routes for both variants.

```ruby
# These all match the same route
Aris::Router.match(domain: "example.com", method: :get, path: "/users")
Aris::Router.match(domain: "example.com", method: :get, path: "/users/")
```

Second, both domains and paths are converted to lowercase. This makes routing case-insensitive, which is generally what you want for URLs.

```ruby
# These also match the same route
Aris::Router.match(domain: "example.com", method: :get, path: "/users")
Aris::Router.match(domain: "EXAMPLE.COM", method: :get, path: "/USERS")
```

Third, URI encoding is decoded automatically. If someone sends a request with URL-encoded characters, Aris decodes them before matching.

```ruby
# URL-encoded space becomes a real space
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/search/hello%20world"
)

result[:params][:query]  # => "hello world"
```

These normalizations happen transparently. You define routes using normal syntax and let Aris handle the edge cases.

### Priority and Precedence

When multiple routes could potentially match a request, Aris uses a strict priority system to choose which one wins. Understanding this system helps you write predictable routes and avoid surprises.

The priority order is: literal segments beat parameterized segments, and parameterized segments beat wildcards.

```ruby
Aris.routes({
  "example.com": {
    "/users": {
      "/new": { get: { to: NewUserHandler } },
      "/:id": { get: { to: ShowUserHandler } }
    }
  }
})

# Matches NewUserHandler (literal wins)
Aris::Router.match(domain: "example.com", method: :get, path: "/users/new")

# Matches ShowUserHandler (parameter matches anything else)
Aris::Router.match(domain: "example.com", method: :get, path: "/users/123")
```

This priority system means you can safely add specific routes without worrying about them being shadowed by more general ones. The literal `/new` route will always match before the parameterized `/:id` route, regardless of the order you define them in the configuration hash.

---

## Path and URL Generation

Matching routes is only half the story. Most applications also need to generate URLs from route definitions. This is where named routes prove their value.

### Basic Path Generation

The `Aris.path` method generates relative paths from named routes. It requires either an explicit domain or a domain context, plus the route name and any necessary parameters.

```ruby
Aris.routes({
  "example.com": {
    "/users/:id": {
      get: { to: UserHandler, as: :user }
    }
  }
})

# Explicit domain (always works)
Aris.path("example.com", :user, id: 123)
# => "/users/123"
```

The method performs several validations. If the named route does not exist, you will get a `RouteNotFoundError`. If you are missing required parameters, you will get an `ArgumentError`. These errors happen immediately, making it easy to catch mistakes during development.

```ruby
# Missing required parameter
Aris.path("example.com", :user)
# => ArgumentError: Missing required param 'id' for route :user

# Nonexistent route
Aris.path("example.com", :nonexistent)
# => Aris::Router::RouteNotFoundError: Named route :nonexistent not found...
```

### Query Parameters

Any parameters you provide that are not used in the path itself become query string parameters automatically.

```ruby
Aris.routes({
  "example.com": {
    "/search": {
      get: { to: SearchHandler, as: :search }
    }
  }
})

Aris.path("example.com", :search, q: "ruby", page: 2, limit: 20)
# => "/search?q=ruby&page=2&limit=20"
```

This behavior makes it easy to build search interfaces and paginated collections. You provide all the parameters you need, and Aris figures out which go in the path and which go in the query string.

### Implicit Domain Context

Specifying the domain every time can be tedious, especially in request handlers where the domain is usually obvious. Aris supports implicit domain context through two mechanisms: a global default domain and thread-local context.

The global default domain is set once and applies everywhere unless overridden.

```ruby
Aris::Router.default_domain = "example.com"

# Now this works without specifying the domain
Aris.path(:user, id: 123)
# => "/users/123"
```

Thread-local context is more dynamic. It is set per-request and automatically cleaned up, making it ideal for web applications where different requests might target different domains.

```ruby
# Set context for this thread
Thread.current[:aris_current_domain] = "admin.example.com"

# Paths use the thread-local domain
Aris.path(:dashboard)  # Uses admin.example.com

# Context is thread-safe—other threads are unaffected
```

In Rack applications, Aris sets the thread-local domain automatically based on the incoming request. This means path generation "just works" in request handlers without any manual setup.

### The with_domain Helper

For temporary context switches, the `with_domain` helper provides a clean block-based interface.

```ruby
Aris.with_domain("admin.example.com") do
  Aris.path(:dashboard)  # Uses admin.example.com
  Aris.path(:users)      # Still uses admin.example.com
end

# Outside the block, we're back to the default domain
```

This is particularly useful when generating URLs for emails or background jobs, where you need to produce links for a specific domain but do not want to change the global context.

### URL Generation

The `Aris.url` method works identically to `Aris.path` but returns absolute URLs instead of relative paths.

```ruby
Aris.url("api.example.com", :users)
# => "https://api.example.com/users"

Aris.url("api.example.com", :user, id: 123, protocol: 'http')
# => "http://api.example.com/users/123"
```

The protocol defaults to `https` but can be overridden with the `protocol:` keyword argument. This is useful for development environments where you might be running on plain HTTP.

---

## HTTP Methods

Aris supports the five standard HTTP methods: GET, POST, PUT, PATCH, and DELETE. Each method is defined separately in your route configuration, allowing you to assign different handlers to different methods on the same path.

### Multiple Methods on One Path

It is common for a single resource to support multiple operations. A user resource might support GET to view, PUT to update, and DELETE to remove.

```ruby
Aris.routes({
  "example.com": {
    "/users/:id": {
      get: { to: UserShowHandler, as: :user },
      put: { to: UserUpdateHandler, as: :user_update },
      delete: { to: UserDeleteHandler, as: :user_delete }
    }
  }
})
```

When a request comes in for `/users/123`, Aris first matches the path, then checks if a handler exists for the specific HTTP method. If the path matches but the method does not, the match returns nil, just as if the path had not matched at all.

This behavior gives you fine-grained control over what operations are allowed on each resource. You might expose read-only access on your public API but allow full CRUD operations on your admin API by simply defining different methods on similar paths across different domains.

### RESTful Resource Routing

While Aris does not include Rails-style resource generators, the hash structure makes it straightforward to define RESTful resources manually.

```ruby
Aris.routes({
  "example.com": {
    "/posts": {
      get: { to: PostsIndexHandler, as: :posts },
      post: { to: PostsCreateHandler, as: :posts_create },
      
      "/:id": {
        get: { to: PostShowHandler, as: :post },
        put: { to: PostUpdateHandler, as: :post_update },
        patch: { to: PostPatchHandler, as: :post_patch },
        delete: { to: PostDeleteHandler, as: :post_delete }
      },
      
      "/new": {
        get: { to: PostNewHandler, as: :post_new }
      },
      
      "/:id/edit": {
        get: { to: PostEditHandler, as: :post_edit }
      }
    }
  }
})
```

This gives you complete control over exactly which routes exist and how they are named. There is no magic generation, but also no hidden routes that you did not explicitly define.

### Method-Specific Named Routes

Notice in the examples above that each method gets its own name. This is optional but recommended. It makes your intent explicit and gives you maximum flexibility when generating URLs.

```ruby
# Update form might POST to a different endpoint than the show page
Aris.url(:post)           # => "https://example.com/posts/123"
Aris.url(:post_update)    # => "https://example.com/posts/123"

# But you can use different methods
[200, {}, [form_for(post, url: Aris.url(:post_update), method: :put)]]
```

If you prefer, you can share names across methods, but this limits your ability to generate method-specific URLs. The choice depends on your application's needs.

---

## Parameters and Wildcards

Parameters and wildcards are the two mechanisms for capturing variable content from request paths. Understanding the differences between them helps you choose the right tool for each situation.

### Parameters

Parameters capture a single path segment. They are defined with a leading colon and must match exactly one segment—they will not match multiple segments or empty values.

```ruby
Aris.routes({
  "example.com": {
    "/posts/:year/:month/:day": {
      get: { to: PostsByDateHandler }
    }
  }
})

# Matches - three segments provided
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/posts/2024/03/15"
)
result[:params]  # => { year: "2024", month: "03", day: "15" }

# Does not match - only two segments
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/posts/2024/03"
)
result  # => nil
```

Parameter names can be anything that forms a valid Ruby symbol. Be descriptive—`:id` is fine for simple cases, but `:user_id` or `:post_id` is clearer when you have nested resources.

```ruby
Aris.routes({
  "example.com": {
    "/users/:user_id/posts/:post_id/comments/:comment_id": {
      get: { to: CommentHandler }
    }
  }
})

result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/1/posts/2/comments/3"
)

result[:params]  
# => { user_id: "1", post_id: "2", comment_id: "3" }
```

### Wildcards

Wildcards capture multiple path segments into a single parameter. They are defined with a leading asterisk and will match zero or more segments.

```ruby
Aris.routes({
  "example.com": {
    "/files/*path": {
      get: { to: FileHandler }
    }
  }
})

# Matches a deep path
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/files/documents/2024/reports/summary.pdf"
)
result[:params]  
# => { path: "documents/2024/reports/summary.pdf" }

# Also matches shallow paths
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/files/readme.txt"
)
result[:params]  # => { path: "readme.txt" }

# Even matches no segments
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/files/"
)
result[:params]  # => { path: "" }
```

The captured value is a string with forward slashes intact. Your handler is responsible for splitting it or otherwise processing it as needed.

Wildcards can also appear in the middle of a path, which is useful for versioned APIs or other creative routing patterns.

```ruby
Aris.routes({
  "api.example.com": {
    "/*version/users": {
      get: { to: ApiUsersHandler }
    }
  }
})

result = Aris::Router.match(
  domain: "api.example.com",
  method: :get,
  path: "/v1/users"
)
result[:params]  # => { version: "v1" }

result = Aris::Router.match(
  domain: "api.example.com",
  method: :get,
  path: "/v2/beta/users"
)
result[:params]  # => { version: "v2/beta" }
```

### Anonymous Wildcards

If you do not need to capture the wildcard value, you can use a bare asterisk without a name. This creates a catch-all route that matches anything but does not add to the params hash.

```ruby
Aris.routes({
  "example.com": {
    "/*": {
      get: { to: CatchAllHandler }
    }
  }
})
```

However, named wildcards are usually clearer. Even if you do not use the captured value immediately, having it in the params hash makes debugging easier and keeps future options open.

---

## File-Based Route Discovery

Instead of defining routes in a hash, you can organize them as files in a directory structure. Aris will scan the directory and automatically generate the route definitions.

### Directory Convention

The directory structure maps directly to routes:

```
routes_dir/
  domain/              # Domain name (use _ for wildcard)
    path/              # Path segments
      _param/          # Parameters (prefix with _)
        method.rb      # HTTP method (get, post, put, etc.)
```

### Examples

**Simple route:**
```
app/routes/example.com/index/get.rb  →  GET / on example.com
```

**Parameterized route:**
```
app/routes/example.com/users/_id/get.rb  →  GET /users/:id on example.com
```

**Nested parameters:**
```
app/routes/example.com/users/_user_id/posts/_post_id/get.rb
  →  GET /users/:user_id/posts/:post_id on example.com
```

**Wildcard domain:**
```
app/routes/_/health/get.rb  →  GET /health on * (any domain)
```

**Multiple HTTP methods:**
```
app/routes/example.com/users/get.rb   →  GET /users
app/routes/example.com/users/post.rb  →  POST /users
```

### Handler Definition

Each route file must define a `Handler` class with a `.call` class method:

```ruby
# app/routes/example.com/users/_id/get.rb
class Handler
  def self.call(request, params)
    user_id = params[:id]
    user = User.find(user_id)
    
    return Aris.not_found(request) unless user
    
    { id: user.id, name: user.name, email: user.email }
  end
end
```

Handlers can return:
- **Hash/Array**: Automatically converted to JSON
- **String**: Returned as plain text
- **Rack response**: `[status, headers, body]` array

### Loading Routes

Use `Aris.discover_and_define` at boot time:

```ruby
# config.ru
require 'aris'

Aris.discover_and_define('app/routes')

run Aris::Adapters::RackApp.new
```

Or discover first and merge with explicit routes:

```ruby
discovered = Aris::Discovery.discover('app/routes')

explicit = {
  "example.com": {
    "/admin": {
      use: [:admin_auth],
      "/dashboard": { get: { to: AdminDashboard } }
    }
  }
}

# Explicit routes can override or extend discovered routes
Aris.routes(explicit.merge(discovered))
```

### Supported HTTP Methods

Discovery recognizes these HTTP methods as filenames:
- `get.rb`
- `post.rb`
- `put.rb`
- `patch.rb`
- `delete.rb`
- `options.rb`

Files with other names (e.g., `invalid.rb`) are ignored.

### Special Cases

**Index files**: A file named `index` represents the root of that path segment.

```ruby
# app/routes/example.com/index/get.rb maps to GET /
# app/routes/example.com/users/index/get.rb maps to GET /users
```

**Domain names**: Use the actual domain name or `_` for wildcard:

```ruby
# app/routes/example.com/         → Routes for example.com
# app/routes/api.example.com/     → Routes for api.example.com  
# app/routes/_/                   → Routes for * (any domain)
```

**Parameters**: Prefix directory names with `_` to indicate parameters:

```ruby
# app/routes/example.com/users/_id/posts/_post_id/get.rb
# The _id becomes :id parameter
# The _post_id becomes :post_id parameter
```

### Handler Namespacing

To prevent conflicts, each handler is automatically namespaced based on its location:

```ruby
# app/routes/example.com/users/get.rb
# Creates: ExampleCom::Users::Get::Handler

# app/routes/example.com/posts/get.rb  
# Creates: ExampleCom::Posts::Get::Handler
```

This allows multiple routes to define a `Handler` class without conflicts.

### Development vs Production

**Development mode** - Reload routes on file changes:

```ruby
if ENV['RACK_ENV'] == 'development'
  require 'listen'
  
  listener = Listen.to('app/routes') do |modified, added, removed|
    puts "Routes changed, reloading..."
    Aris.discover_and_define('app/routes')
  end
  
  listener.start
end
```

**Production mode** - Load once at boot:

```ruby
# Discovery happens once during boot
Aris.discover_and_define('app/routes')
# Handlers are compiled into the route trie
# No file I/O during request handling
```

### Performance Considerations

File-based discovery happens **once at boot time**, not at request time. After discovery:

- Handlers are loaded into memory as Ruby classes
- Routes are compiled into Aris's optimized trie structure  
- Request handling is identical to hash-defined routes (570ns-1.31μs per match)
- No file I/O or dynamic loading during requests

Discovery time scales linearly: approximately 0.2-0.5ms per route. For a typical app with 100 routes, discovery takes 20-50ms at boot.

### Error Handling

Discovery gracefully handles errors:

**Missing Handler constant:**
```ruby
# File doesn't define Handler class
# Warning logged, route skipped
```

**Syntax errors:**
```ruby
# File has invalid Ruby syntax
# Warning logged, route skipped
```

**Handler without .call method:**
```ruby
# Handler class doesn't respond to .call
# Warning logged, route skipped
```

Check your logs at boot time for any warnings about skipped routes.

### Testing

Test handlers in isolation:

```ruby
# test/routes/users_get_test.rb
require 'test_helper'

# Load the handler directly
require_relative '../../app/routes/example.com/users/get'

class UsersGetTest < Minitest::Test
  def test_returns_user_list
    # Handler is namespaced
    result = ExampleCom::Users::Get::Handler.call(mock_request, {})
    
    assert_kind_of Array, result
    assert result.any?
  end
end
```

Or test through the router:

```ruby
def test_users_route
  Aris.discover_and_define('app/routes')
  
  result = Aris::Router.match(
    domain: "example.com",
    method: :get,
    path: "/users"
  )
  
  assert result
  assert_respond_to result[:handler], :call
end
```

### Comparison with Hash Definition

**File-based (discovery):**
```
Pros:
- Organized by domain and path
- Easy to find handlers
- Scales well with many routes
- Clear file-per-route structure

Cons:  
- Slightly slower boot time (0.2-0.5ms per route)
- Requires file system
```

**Hash-based (explicit):**
```
Pros:
- Instant definition (no file I/ O)
- Can use dynamic handler creation
- All routes visible in one place

Cons:
- Large hash for many routes
- Harder to navigate
```

Most apps benefit from using both: file-based discovery for standard routes, hash definition for special cases or dynamic routes.

---

## Constraints

Constraints validate parameter values at the routing level, before any handler code runs. This creates a fail-fast system where invalid requests never reach your application logic.

### Basic Constraints

Constraints are defined with the `constraints:` option and use regular expressions to match parameter values.

```ruby
Aris.routes({
  "example.com": {
    "/users/:id": {
      get: {
        to: UserHandler,
        as: :user,
        constraints: { id: /\A\d{1,8}\z/ }  # 1-8 digit numbers only
      }
    }
  }
})

# Matches - valid numeric ID
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/12345"
)
result[:handler]  # => UserHandler

# Does not match - alphabetic characters
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/admin"
)
result  # => nil

# Does not match - too many digits
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/123456789"
)
result  # => nil
```

When a constraint fails, the entire route fails. Aris will try other routes that might match the path, respecting the usual priority rules. If no routes match, the match returns nil, just as if the path had not matched in the first place.

### Multiple Constraints

You can constrain multiple parameters in a single route. Each parameter is validated independently.

```ruby
Aris.routes({
  "example.com": {
    "/posts/:year/:month/:day": {
      get: {
        to: PostsByDateHandler,
        constraints: {
          year: /\A\d{4}\z/,      # Four-digit year
          month: /\A(0[1-9]|1[0-2])\z/,  # 01-12
          day: /\A(0[1-9]|[12]\d|3[01])\z/  # 01-31
        }
      }
    }
  }
})

# Matches - all constraints pass
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/posts/2024/03/15"
)
result[:params]  # => { year: "2024", month: "03", day: "15" }

# Does not match - invalid month
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/posts/2024/13/15"
)
result  # => nil
```

All constraints must pass for the route to match. If even one fails, the entire route is rejected.

### Constraints and Route Priority

Constraints are evaluated after path structure matches but before the route is considered valid. This means you can have multiple routes with the same path structure but different constraints, and Aris will try them in priority order.

```ruby
Aris.routes({
  "example.com": {
    "/users": {
      "/:id": {
        get: {
          to: NumericUserHandler,
          constraints: { id: /\A\d+\z/ }
        }
      },
      "/:username": {
        get: {
          to: UsernameUserHandler,
          constraints: { username: /\A[a-z]+\z/ }
        }
      }
    }
  }
})
```

However, this pattern is tricky and not generally recommended. Because both routes have the same path structure (`/:id` and `/:username` both match a single segment), Aris treats them as the same route structurally. Only one will actually be used, based on the order they appear in the hash.

A better approach is to use distinct path structures:

```ruby
Aris.routes({
  "example.com": {
    "/users": {
      "/id/:id": {
        get: {
          to: NumericUserHandler,
          constraints: { id: /\A\d+\z/ }
        }
      },
      "/username/:username": {
        get: {
          to: UsernameUserHandler,
          constraints: { username: /\A[a-z]+\z/ }
        }
      }
    }
  }
})
```

This makes the intent explicit and avoids any ambiguity about which route should match.

### Common Constraint Patterns

Here are some useful constraint patterns for common validation needs:

```ruby
# Numeric IDs
id: /\A\d+\z/

# Limited-length numeric IDs (prevents very large numbers)
id: /\A\d{1,10}\z/

# URL-safe slugs
slug: /\A[a-z0-9\-]+\z/

# Uppercase codes (like country codes)
country: /\A[A-Z]{2}\z/

# UUIDs
uuid: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

# Alphanumeric tokens
token: /\A[a-zA-Z0-9]{20,}\z/

# Dates in YYYY-MM-DD format
date: /\A\d{4}-\d{2}-\d{2}\z/
```

These patterns provide a first line of defense against malformed input, but they should not be your only validation. Always validate data again in your handlers, especially for business logic constraints that go beyond format validation.

---

## Multi-Domain Routing

Modern web applications often span multiple domains. Your marketing site might be on `example.com`, your app on `app.example.com`, your API on `api.example.com`, and your admin panel on `admin.example.com`. Aris treats domains as first-class routing primitives, making multi-domain applications straightforward to build.

### Domain-Level Isolation

Each domain in your routing configuration gets its own independent routing tree. Routes defined on one domain do not interfere with routes on another domain, even if they have identical paths.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: MarketingHomeHandler } },
    "/pricing": { get: { to: PricingHandler } },
    "/contact": { get: { to: ContactHandler } }
  },
  
  "app.example.com": {
    "/": { get: { to: AppDashboardHandler } },
    "/projects": { get: { to: ProjectsHandler } },
    "/settings": { get: { to: SettingsHandler } }
  },
  
  "api.example.com": {
    "/v1": {
      "/users": { get: { to: ApiUsersHandler } },
      "/projects": { get: { to: ApiProjectsHandler } }
    }
  }
})
```

Notice that both `example.com` and `app.example.com` have a root route, and both `app.example.com` and `api.example.com` have a `/projects` route. These do not conflict because the domain is always part of the routing decision.

When a request comes in, Aris first looks up the domain in the routing table. If found, it searches that domain's tree for a matching path. If not found, it falls back to the wildcard domain (if one is defined). The domain is never ambiguous.

### Handling Multi-Tenant Subdomains

For applications where each tenant gets their own subdomain (like `tenant-a.acme.com` and `tenant-b.acme.com`), you should not define a separate route for every tenant. Instead, route to a general domain and extract the tenant identifier from the hostname in your application code.

Aris does not support dynamic wildcard domains in route definitions (you cannot use `*.acme.com` as a domain key). However, you can achieve multi-tenant subdomain routing by pointing all tenant traffic to a single domain endpoint via DNS configuration, then processing the full hostname in your handlers or plugins.

```ruby
# All tenant traffic points to this domain via DNS CNAME
Aris.routes({
  "app.acme.com": {
    "/": { get: { to: TenantDashboardHandler } },
    "/settings": { get: { to: TenantSettingsHandler } }
  }
})

# In your handler or a plugin:
class TenantDashboardHandler
  def self.call(request, params)
    # request.domain contains the full hostname: "tenant-a.acme.com"
    subdomain = request.domain.split('.').first
    tenant = Tenant.find_by(subdomain: subdomain)
    
    return Aris.not_found(request) unless tenant
    
    # Use tenant data to customize the response
    [200, {}, ["Welcome to #{tenant.name}'s Dashboard"]]
  end
end
```

This pattern keeps your routing configuration clean and static while allowing for infinite dynamic subdomains handled by your application logic. The routing structure stays simple, and tenant-specific behavior lives in your handlers where it belongs.

### The Wildcard Domain Fallback

The special `"*"` domain acts as a catch-all for requests that do not match any specific domain. This is perfect for infrastructure routes like health checks that should work on any domain.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  },
  
  "app.example.com": {
    "/dashboard": { get: { to: DashboardHandler } }
  },
  
  "*": {
    "/health": { get: { to: HealthCheckHandler } },
    "/version": { get: { to: VersionHandler } }
  }
})
```

Now `/health` and `/version` will work on any domain—`example.com/health`, `app.example.com/health`, `unknown.example.com/health`, and so on. The wildcard domain is checked only if no specific domain matches.

This fallback behavior is important to understand. If you define a `/health` route on `example.com` and also on `"*"`, a request to `example.com/health` will match the specific domain route, not the wildcard. Specific domains always take precedence.

### Cross-Domain URL Generation

When generating URLs in a multi-domain application, you typically need to specify which domain you are targeting. This is where explicit domain in path helpers shines.

```ruby
# Generate URLs for different domains
marketing_url = Aris.url("example.com", :home)
# => "https://example.com/"

app_url = Aris.url("app.example.com", :dashboard)
# => "https://app.example.com/dashboard"

api_url = Aris.url("api.example.com", :users)
# => "https://api.example.com/v1/users"
```

In request handlers, you can use the thread-local domain context to default to the current domain while still being able to generate cross-domain links when needed.

```ruby
class DashboardHandler
  def self.call(request, params)
    # Current domain link (uses thread-local context)
    settings_link = Aris.path(:settings)
    
    # Cross-domain link (explicit domain)
    api_link = Aris.url("api.example.com", :users)
    
    [200, {}, ["Dashboard with links"]]
  end
end
```

---

## The Plugin System

Plugins (also called middleware or filters in other frameworks) let you run code before your handlers execute. They are perfect for cross-cutting concerns like authentication, logging, rate limiting, and response modification.

### Plugin Basics

A plugin is any callable object that implements `call(request, response)`. It receives the current request and a mutable response object. It can inspect the request, modify the response, or halt processing entirely by returning the response object.

```ruby
class SimpleLogger
  def self.call(request, response)
    puts "Request: #{request.method} #{request.path}"
    nil  # Return nil to continue processing
  end
end

class Authentication
  def self.call(request, response)
    token = request.headers['HTTP_AUTHORIZATION']
    
    if token != 'valid-token'
      response.status = 401
      response.body = ['Unauthorized']
      return response  # Return response to halt processing
    end
    
    nil  # Return nil to continue
  end
end
```

The contract is simple: if you return nil (or anything that is not a response object), processing continues to the next plugin or handler. If you return a response object, processing stops immediately and that response is sent to the client.


### Registering Plugins

Before using plugins in routes, register them with a symbol name. This lets you reference plugins cleanly in your route configuration.

```ruby
# Register a single plugin
class RateLimiter
  def self.call(request, response)
    # Implementation
  end
end

Aris.register_plugin(:rate_limit, plugin_class: RateLimiter)

# Register multi-class plugins (like CSRF with separate generator and protection)
Aris.register_plugin(:csrf,
  generator: CsrfTokenGenerator,
  protection: CsrfProtection
)

# Now use them in routes via symbols
Aris.routes({
  "api.example.com": {
    use: [:rate_limit, :csrf],  # Symbols resolve to plugin classes
    "/users": { get: { to: UsersHandler } }
  }
})
```

Registered symbols expand to their plugin classes at compile time. Multi-class plugins like `:csrf` expand to all their components in order (generator, then protection).

### Applying Plugins

Plugins are applied using the `use:` key at three levels: domain, scope, and route. Plugins inherit down the tree and are executed in the order they appear.

```ruby
Aris.routes({
  "api.example.com": {
    use: [:cors, :rate_limit],  # Domain-level - using registered symbols
    
    "/public": {
      "/status": { get: { to: StatusHandler } }
    },
    
    "/private": {
      use: [:authentication],  # Scope-level (inherits :cors, :rate_limit)
      "/users": { get: { to: UsersHandler } }
    }
  }
})
```

In this example:
- Requests to `/public/status` run through CORS and rate limiting plugins
- Requests to `/private/users` run through CORS, rate limiting, and authentication plugins

The scope-level plugin adds to the domain-level plugins rather than replacing them. This composition model makes it easy to build layered security and functionality.

### Route-Level Plugins

You can also apply plugins to individual routes. Route-level plugins merge with inherited plugins.

```ruby
Aris.routes({
  "example.com": {
    use: [CorsHeaders],
    
    "/users/:id": {
      get: {
        to: UserHandler,
        use: [CorsHeaders, CacheControl]  # Merges with domain-level
      }
    }
  }
})
```

A request to `/users/123` will run through `CorsHeaders` (from domain level) and `CacheControl` (from route level). The router automatically deduplicates plugins, so if the same plugin appears at multiple levels, it only runs once.

### Clearing Inherited Plugins

Sometimes you need to opt out of inherited plugins. Health check endpoints often fall into this category—you want them to run without authentication or rate limiting so monitoring systems can reach them reliably.

```ruby
Aris.routes({
  "example.com": {
    use: [Authentication, RateLimiter],
    
    "/users": {
      get: { to: UsersHandler }  # Runs through Authentication, RateLimiter
    },
    
    "/health": {
      use: nil,  # Clears all inherited plugins
      get: { to: HealthHandler }
    }
  }
})
```

Setting `use: nil` at any level clears all inherited plugins from that point down. The route runs with no plugins at all, as if it were defined at the top level without any `use:` keys above it.

### Plugin Execution Order

Plugins execute in the order they appear in the combined list. Understanding this order is important when plugins depend on each other.

```ruby
Aris.routes({
  "api.example.com": {
    use: [:cors, :authentication, :rate_limit],  # Using registered plugin symbols
    
    "/users": { get: { to: UsersHandler } }
  }
})
```

For a request to `/users`:
1. `CorsHeaders` runs first and adds CORS headers to the response
2. `Authentication` runs second and checks if the request is authorized
3. `RateLimiter` runs third and checks if the request is within rate limits
4. If all plugins return nil, `UsersHandler` executes

If any plugin returns a response object, execution stops immediately. If `Authentication` returns a 401 response, `RateLimiter` never runs and neither does the handler.

This early-exit behavior is powerful. It means expensive operations like rate limit checks only run for authenticated requests. You can structure your plugin order to fail fast on the cheapest checks.

### Modifying the Response

Plugins receive a mutable response object. Any changes you make to it will be visible to subsequent plugins and the final response.

```ruby
class ResponseTimer
  def self.call(request, response)
    start_time = Time.now
    
    # Store start time in the response object for later use
    response.headers['X-Request-Start'] = start_time.to_f.to_s
    
    nil  # Continue processing
  end
end

class ResponseFinalizer
  def self.call(request, response)
    if start_time = response.headers['X-Request-Start']
      duration = Time.now.to_f - start_time.to_f
      response.headers['X-Request-Duration'] = duration.to_s
    end
    
    nil  # Continue processing
  end
end

Aris.routes({
  "api.example.com": {
    use: [ResponseTimer, ResponseFinalizer],
    "/users": { get: { to: UsersHandler } }
  }
})
```

This pattern of setting state in the response and reading it later is a simple way to share data between plugins without relying on global variables or thread-local state.

### Plugin Patterns

Here are some common plugin patterns that solve real problems:

**Setting Headers**

```ruby
class SecurityHeaders
  def self.call(request, response)
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-content-type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    nil
  end
end
```

**Content Negotiation**

```ruby
class JsonResponder
  def self.call(request, response)
    response.headers['content-type'] = 'application/json'
    nil
  end
end
```

**Request Logging**

```ruby
class RequestLogger
  def self.call(request, response)
    RequestLog.create(
      method: request.method,
      path: request.path,
      domain: request.domain,
      timestamp: Time.now
    )
    nil
  end
end
```

**Rate Limiting**

```ruby
class RateLimiter
  def self.call(request, response)
    key = request.headers['HTTP_X_API_KEY']
    
    if rate_limit_exceeded?(key)
      response.status = 429
      response.headers['Retry-After'] = '60'
      response.body = ['Rate limit exceeded']
      return response
    end
    
    increment_rate_limit(key)
    nil
  end
  
  def self.rate_limit_exceeded?(key)
    # Check Redis or similar
  end
  
  def self.increment_rate_limit(key)
    # Increment counter in Redis
  end
end
```

---

## Error Handling

Production applications need robust error handling. Aris separates routing failures (404s) from application errors (500s) and provides declarative handlers for both.

### Configuring Error Handlers

Error handlers are set globally using `Aris.default`. These handlers are callables that return Rack-compatible response arrays.

```ruby
class Custom404
  def self.call(request, params)
    [404, 
     {'content-type' => 'application/json'},
     ['{"error": "Not found", "path": "' + request.path + '"}']]
  end
end

class Custom500
  def self.call(request, exception)
    # Log to your error tracking service
    ErrorTracker.report(exception, {
      request_path: request.path,
      request_method: request.method
    })
    
    # Return a safe error response
    [500,
     {'content-type' => 'application/json'},
     ['{"error": "Internal server error"}']]
  end
end

Aris.default(
  not_found: Custom404,
  error: Custom500,
  default_host: 'example.com'
)
```

Once configured, these handlers are used automatically when errors occur. You do not need to rescue exceptions in every handler or check for nil routes in every controller. The error handling is centralized and consistent.

### The 404 Flow

A 404 occurs in two situations: when no route matches the incoming request, or when you explicitly trigger it from your application code.

The first case happens automatically. If `Aris::Router.match` returns nil, the Rack adapter calls your configured 404 handler.

```ruby
# No route defined for this path
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/nonexistent"
)
# => nil

# In the Rack adapter, this triggers:
Aris.not_found(request)
```

The second case gives you control. When your handler determines that a resource does not exist, call `Aris.not_found` to trigger the 404 handler.

```ruby
class UserHandler
  def self.call(request, params)
    user = User.find_by(id: params[:id])
    
    # Explicitly trigger 404 if user not found
    return Aris.not_found(request) unless user
    
    # Normal response if user exists
    [200, {}, [user.to_json]]
  end
end
```

This pattern keeps your handlers clean. You do not need conditional logic to return different response formats—just call `not_found` and the configured handler takes care of formatting and logging.

### The 500 Flow

A 500 occurs when an exception is raised during request processing. This includes exceptions from plugins and handlers.

```ruby
class PaymentHandler
  def self.call(request, params)
    # This might raise if the payment gateway is down
    PaymentGateway.charge(params[:amount])
  rescue PaymentGateway::Error => e
    # Explicitly trigger 500 handler
    return Aris.error(request, e)
  end
end
```

You can also let exceptions bubble up naturally. The Rack adapter catches all unhandled exceptions and routes them to your configured 500 handler automatically.

```ruby
class DataHandler
  def self.call(request, params)
    # If this raises, Rack adapter catches it and calls error handler
    critical_operation_that_might_fail
  end
end
```

Both approaches work. Explicitly calling `Aris.error` gives you control over which exceptions are treated as 500s versus which should crash the application. Letting exceptions bubble is simpler but less selective.

### The Redirect Helper

The `Aris.redirect` method provides a clean way to return redirect responses from handlers.

```ruby
class LegacyUserHandler
  def self.call(request, params)
    # Redirect to the new endpoint
    Aris.redirect(:user_show, id: params[:id], status: 301)
  end
end
```

The method accepts either a named route (as a symbol) or a string URL. It returns a Rack-compatible response array with the appropriate status code and Location header.

```ruby
# Named route redirect
Aris.redirect(:home)
# => [302, {'Location' => 'https://example.com/'}, []]

# Named route with parameters
Aris.redirect(:user, id: 123, status: 301)
# => [301, {'Location' => 'https://example.com/users/123'}, []]

# Direct URL redirect
Aris.redirect('https://external-site.com/resource')
# => [302, {'Location' => 'https://external-site.com/resource'}, []]
```

The default status is 302 (temporary redirect), but you can specify any redirect status code with the `status:` keyword argument.

### Error Handler Best Practices

Error handlers are the last line of defense. They should never raise exceptions themselves, or you risk crashing the application with no way to recover.

Always include fallback logic in your error handlers:

```ruby
class SafeErrorHandler
  def self.call(request, exception)
    begin
      # Try to log the exception
      ErrorTracker.report(exception)
    rescue => e
      # If logging fails, fall back to simple logging
      puts "Error tracking failed: #{e.message}"
      puts "Original exception: #{exception.message}"
    end
    
    # Always return a valid response
    [500, {'content-type' => 'text/plain'}, ['Internal Server Error']]
  end
end
```

Be careful about information disclosure. Error messages in production should not reveal stack traces, database queries, or other implementation details. Save the detailed information for your logs.

```ruby
class ProductionErrorHandler
  def self.call(request, exception)
    # Detailed logging
    logger.error("Exception: #{exception.class}: #{exception.message}")
    logger.error(exception.backtrace.join("\n"))
    
    # Generic response
    [500,
     {'content-type' => 'application/json'},
     ['{"error": "An error occurred. Please try again later."}']]
  end
end
```

---

## Rack Integration

Aris ships with a Rack adapter that handles the complete request/response cycle. The adapter bridges between Rack's HTTP-level interface and Aris's routing-level interface, managing request parsing, plugin execution, error handling, and response formatting automatically.

### Basic Rack Setup

The simplest Rack integration looks like this:

```ruby
# config.ru
require 'aris'

Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  }
})

run Aris::Adapters::RackApp.new
```

That is all you need for a working Rack application. The adapter handles everything else: parsing the Rack environment, calling the router, executing plugins, formatting responses, and managing errors.

### Request and Response Objects

The Rack adapter translates between Rack's environment hash and Aris's request/response objects. These objects provide a clean, framework-agnostic interface that works the same whether you are in a Rack app, a CLI tool, or a custom server.

The request object exposes common attributes:

```ruby
class ExampleHandler
  def self.call(request, params)
    request.method       # "GET", "POST", etc.
    request.path         # "/users/123"
    request.domain       # "example.com"
    request.host         # "example.com" (alias for domain)
    request.query        # "page=2&limit=10"
    request.headers      # Hash of HTTP headers
    request.body         # Raw request body as string
    request.params       # Parsed query parameters
    
    [200, {}, ["OK"]]
  end
end
```

These attributes are lazy. The query parameters are not parsed until you access `request.params`. The body is not read until you access `request.body`. This keeps request processing fast when you do not need all the data.

The response object is mutable and starts with safe defaults:

```ruby
response = Aris::Response.new
response.status    # => 200
response.headers   # => {'content-type' => 'text/html'}
response.body      # => []
```

Plugins and handlers can modify the response before it is sent:

```ruby
class JsonHandler
  def self.call(request, params)
    response = Aris::Response.new
    response.status = 201
    response.headers['content-type'] = 'application/json'
    response.body = ['{"created": true}']
    response
  end
end
```

### Handler Types

The Rack adapter supports three handler types, giving you flexibility in how you structure your application.

**Callable Classes**

This is the most common pattern. A class with a `self.call` method that takes request and params.

```ruby
class UserHandler
  def self.call(request, params)
    user = User.find(params[:id])
    [200, {}, [user.to_json]]
  end
end

Aris.routes({
  "example.com": {
    "/users/:id": { get: { to: UserHandler } }
  }
})
```

**Procs and Lambdas**

For simple handlers, inline procs keep everything in one place.

```ruby
home_handler = ->(request, params) {
  [200, {}, ["<h1>Home</h1>"]]
}

Aris.routes({
  "example.com": {
    "/": { get: { to: home_handler } }
  }
})
```

**Controller Strings**

For compatibility with Rails-style conventions, you can use strings in the format "ClassName#method".

```ruby
Aris.routes({
  "example.com": {
    "/users/:id": { get: { to: "Users::Controller#show" } }
  }
})

module Users
  class Controller
    def show(request, params)
      user = User.find(params[:id])
      [200, {}, [user.to_json]]
    end
  end
end
```

The adapter instantiates the class and calls the named method with the request and params. This pattern is less common in Aris applications but can ease migration from other frameworks.

### Response Formats

Handlers can return multiple response formats, and the adapter normalizes them to Rack-compatible arrays.

**Full Rack Array**

The most explicit format is a three-element array: status code, headers hash, and body array.

```ruby
def self.call(request, params)
  [200, {'content-type' => 'text/plain'}, ['Hello World']]
end
```

**Hash**

Returning a hash automatically converts it to JSON with appropriate headers.

```ruby
def self.call(request, params)
  { user_id: params[:id], name: "Alice" }
end

# Automatically becomes:
# [200, {'content-type' => 'application/json'}, ['{"user_id":"123","name":"Alice"}']]
```

**String**

Returning a plain string wraps it in a text/plain response.

```ruby
def self.call(request, params)
  "Hello World"
end

# Automatically becomes:
# [200, {'content-type' => 'text/plain'}, ['Hello World']]
```

**Response Object**

Returning an `Aris::Response` object uses it directly. This is mainly for plugins that need to halt processing.

```ruby
def self.call(request, params)
  response = Aris::Response.new
  response.status = 201
  response.headers['X-Custom'] = 'Header'
  response.body = ['Created']
  response
end
```

This flexibility means you can write handlers in whatever style feels natural and let the adapter handle the details.

### Thread-Local Domain Context

The Rack adapter automatically sets thread-local domain context for each request. This makes path and URL helpers work without explicit domain parameters.

```ruby
class DashboardHandler
  def self.call(request, params)
    # These work without specifying domain
    # because Rack adapter set Thread.current[:aris_current_domain]
    user_path = Aris.path(:user, id: params[:id])
    settings_path = Aris.path(:settings)
    
    [200, {}, ["<a href='#{user_path}'>User</a>"]]
  end
end
```

The context is set at the start of each request and cleaned up at the end, ensuring thread safety in multi-threaded servers like Puma.

### Middleware Composition

Aris's Rack adapter is itself just Rack middleware. You can compose it with other Rack middleware for HTTP-level concerns.

```ruby
# config.ru
require 'aris'
require 'rack/ssl'
require 'rack/deflater'

Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler } }
  }
})

# Rack middleware runs before routing
use Rack::SSL
use Rack::Deflater

# Aris plugins run after routing
run Aris::Adapters::RackApp.new
```

This layering gives you the best of both worlds: Rack middleware for HTTP concerns like SSL, compression, and static files; Aris plugins for application concerns like authentication and authorization.

---

## Standalone Usage

Aris's agnostic design makes it useful beyond web applications. The routing engine is just a function—give it a domain, method, and path, get back routing metadata. You can call it from anywhere.

### CLI Applications

Command-line tools often need to route user input to different handlers. Aris makes this natural.

```ruby
#!/usr/bin/env ruby
require 'aris'

# Define routes for CLI commands
Aris.routes({
  "cli.internal": {
    "/users": {
      "/list": { get: { to: UserListCommand } },
      "/:id": {
        "/show": { get: { to: UserShowCommand } },
        "/delete": { delete: { to: UserDeleteCommand } }
      }
    },
    "/projects": {
      "/list": { get: { to: ProjectListCommand } },
      "/create": { post: { to: ProjectCreateCommand } }
    }
  }
})

# Parse command line arguments into a route
# Example: ./cli users 123 show
domain = "cli.internal"
method = :get
path = "/" + ARGV.join("/")

result = Aris::Router.match(
  domain: domain,
  method: method,
  path: path
)

if result
  # Extract command handler and execute it
  handler = result[:handler]
  params = result[:params]
  
  handler.call(params)
else
  puts "Unknown command: #{ARGV.join(' ')}"
  puts "Try: users list, users 123 show, projects create, etc."
  exit 1
end
```

This approach gives you all the benefits of Aris's routing—parameter extraction, constraints, nested commands—in a non-web context.

### Background Jobs

Background job systems often need to route different types of jobs to different processors. Aris can replace conditional logic with declarative routing.

```ruby
# Define routes for different job types
Aris.routes({
  "jobs.internal": {
    "/emails": {
      "/welcome": { post: { to: WelcomeEmailJob } },
      "/notification": { post: { to: NotificationEmailJob } }
    },
    "/reports": {
      "/daily": { post: { to: DailyReportJob } },
      "/weekly": { post: { to: WeeklyReportJob } }
    },
    "/webhooks": {
      "/:provider/:event": { post: { to: WebhookProcessor } }
    }
  }
})

class JobRouter
  def self.perform(job_type, payload)
    # Convert job type to a path
    path = "/#{job_type.gsub(':', '/')}"
    
    result = Aris::Router.match(
      domain: "jobs.internal",
      method: :post,
      path: path
    )
    
    if result
      result[:handler].call(payload, result[:params])
    else
      raise "Unknown job type: #{job_type}"
    end
  end
end

# Usage
JobRouter.perform("emails:welcome", { user_id: 123 })
JobRouter.perform("webhooks:stripe:payment_success", { amount: 5000 })
```

This pattern makes job routing explicit and testable. Adding a new job type is as simple as adding a new route.

### Custom Servers

If you are building a custom HTTP server using FFI bindings to C or Rust, Aris integrates seamlessly because it does not assume anything about how requests arrive.

```ruby
class CustomServerAdapter
  def initialize
    @router = Aris::Router
  end
  
  def handle_request(native_request)
    # Translate from your server's request format
    result = @router.match(
      domain: native_request.hostname,
      method: native_request.verb.downcase.to_sym,
      path: native_request.uri_path
    )
    
    # Handle 404
    unless result
      return native_response(404, "Not Found")
    end
    
    # Execute handler
    handler = result[:handler]
    
    # Create a lightweight request wrapper
    request = RequestWrapper.new(native_request)
    response = handler.call(request, result[:params])
    
    # Translate back to your server's response format
    translate_to_native_response(response)
  end
  
  private
  
  def translate_to_native_response(response)
    status, headers, body = response
    
    native_response = NativeResponse.new
    native_response.status_code = status
    headers.each { |k, v| native_response.set_header(k, v) }
    native_response.body = body.join
    native_response
  end
end
```

This adapter pattern lets you swap servers without changing your application code. Your handlers work the same whether running on Puma, a custom Rust server, or anything else.

### Testing

Aris's standalone mode makes testing straightforward. You can test routing without spinning up a web server.

```ruby
require 'minitest/autorun'

class RoutingTest < Minitest::Test
  def setup
    Aris.routes({
      "example.com": {
        "/users/:id": { get: { to: UserHandler, as: :user } }
      }
    })
  end
  
  def test_user_route_matches
    result = Aris::Router.match(
      domain: "example.com",
      method: :get,
      path: "/users/123"
    )
    
    assert_equal UserHandler, result[:handler]
    assert_equal "123", result[:params][:id]
  end
  
  def test_nonexistent_route_returns_nil
    result = Aris::Router.match(
      domain: "example.com",
      method: :get,
      path: "/posts/1"
    )
    
    assert_nil result
  end
  
  def test_path_generation
    path = Aris.path("example.com", :user, id: 456)
    assert_equal "/users/456", path
  end
end
```

You can test handlers in isolation by calling them directly with mock request objects:

```ruby
class HandlerTest < Minitest::Test
  def test_user_handler_returns_json
    request = MockRequest.new(domain: "example.com", method: "GET", path: "/users/1")
    params = { id: "1" }
    
    status, headers, body = UserHandler.call(request, params)
    
    assert_equal 200, status
    assert_equal 'application/json', headers['content-type']
    assert_includes body.first, '"id":"1"'
  end
end
```

This separation of concerns—routing logic separate from handler logic separate from HTTP concerns—makes every piece independently testable.

---

## Advanced Patterns

Once you understand the basics, you can use Aris's flexibility to implement sophisticated patterns that would be awkward in other routers.

### Dynamic Route Generation

Since routes are just data, you can generate them programmatically. This is useful for multi-tenant systems, plugin architectures, or API versioning.

```ruby
# Generate routes for multiple API versions
def build_api_routes
  versions = [1, 2, 3]
  routes = {}
  
  versions.each do |version|
    routes["api.example.com/v#{version}"] = {
      "/users" => { get: { to: "Api::V#{version}::UsersHandler".constantize } },
      "/posts" => { get: { to: "Api::V#{version}::PostsHandler".constantize } }
    }
  end
  
  routes
end

Aris.routes(build_api_routes)
```

This pattern keeps your routing DRY while maintaining explicit control over which versions exist and what they do.

### Loading Routes from Configuration Files

For truly dynamic applications, you can load routes from YAML, JSON, or a database.

```ruby
# config/routes.yml
example.com:
  /:
    get:
      to: HomeHandler
      as: home
  /users/:id:
    get:
      to: UserHandler
      as: user

# In your application
require 'yaml'

config = YAML.load_file('config/routes.yml')
Aris.routes(config)
```

This approach lets non-developers edit routes through a CMS or admin interface, or lets you A/B test different routing structures without deploying code.

### Composing Route Configurations

Large applications benefit from splitting route definitions across multiple files. Since routes are just hashes, merging them is straightforward.

```ruby
# config/routes/public.rb
module Routes
  PUBLIC = {
    "example.com": {
      "/": { get: { to: HomeHandler } },
      "/about": { get: { to: AboutHandler } }
    }
  }
end

# config/routes/api.rb
module Routes
  API = {
    "api.example.com": {
      "/v1": {
        "/users": { get: { to: ApiUsersHandler } }
      }
    }
  }
end

# config/routes.rb
require_relative 'routes/public'
require_relative 'routes/api'

Aris.routes(Routes::PUBLIC.merge(Routes::API))
```

You can get more sophisticated with deep merging for nested structures, but the basic pattern is simple: routes are data, so use normal Ruby data manipulation techniques.

### Conditional Routing

Sometimes you need different routes in different environments. Since route definition is just code that runs at boot time, conditionals work naturally.

```ruby
routes = {
  "example.com": {
    "/": { get: { to: HomeHandler } }
  }
}

if ENV['RAILS_ENV'] == 'development'
  routes["example.com"]["/debug"] = {
    get: { to: DebugHandler }
  }
end

if FeatureFlags.enabled?(:new_api)
  routes["api.example.com"] = {
    "/v2": {
      "/users": { get: { to: ApiV2UsersHandler } }
    }
  }
end

Aris.routes(routes)
```

This lets you feature-flag entire sections of your routing tree or expose debugging routes only in development.

### Nested Resource Routing

While Aris does not include resource generators, you can build your own helpers for common patterns.

```ruby
def resource(name, &block)
  {
    name => {
      get: { to: "#{name.capitalize}IndexHandler".constantize, as: name.to_sym },
      post: { to: "#{name.capitalize}CreateHandler".constantize },
      
      "/:id" => {
        get: { to: "#{name.capitalize}ShowHandler".constantize, as: "#{name}_show".to_sym },
        put: { to: "#{name.capitalize}UpdateHandler".constantize },
        delete: { to: "#{name.capitalize}DeleteHandler".constantize }
      }
    }
  }
end

routes = {
  "example.com": resource("users").merge(resource("posts"))
}

Aris.routes(routes)
```

This gives you the convenience of resource routing while keeping full control over what gets generated.

### Handler Composition

Since handlers are just callables, you can compose them using normal Ruby patterns.

```ruby
module Handlers
  def self.with_caching(handler, ttl: 60)
    ->(request, params) {
      cache_key = "#{request.path}:#{params.to_json}"
      
      if cached = Cache.get(cache_key)
        return cached
      end
      
      response = handler.call(request, params)
      Cache.set(cache_key, response, ttl: ttl)
      response
    }
  end
end

Aris.routes({
  "example.com": {
    "/expensive": {
      get: { 
        to: Handlers.with_caching(ExpensiveHandler, ttl: 300)
      }
    }
  }
})
```

This decorator pattern lets you add cross-cutting concerns at the handler level without modifying handler classes or building plugin infrastructure.

---

## Complete API Reference

### Aris Module Methods

**`Aris.routes(config)`**

Defines the routing table. Takes a hash where keys are domains and values are path configurations. Performs a complete reset and recompilation of the routing structure.

```ruby
Aris.routes({
  "example.com": {
    "/": { get: { to: HomeHandler, as: :home } }
  }
})
```

**`Aris.path(*args, **params)`**

Generates a relative path from a named route.

```ruby
# With explicit domain
Aris.path("example.com", :user, id: 123)
# => "/users/123"

# With implicit domain (requires context)
Aris.path(:user, id: 123)
# => "/users/123"
```

Raises `RouteNotFoundError` if the route name does not exist. Raises `ArgumentError` if required parameters are missing.

**`Aris.url(*args, protocol: 'https', **params)`**

Generates an absolute URL from a named route.

```ruby
Aris.url("example.com", :user, id: 123)
# => "https://example.com/users/123"

Aris.url("example.com", :user, id: 123, protocol: 'http')
# => "http://example.com/users/123"
```

**`Aris.with_domain(domain, &block)`**

Temporarily sets the domain context for the duration of the block.

```ruby
Aris.with_domain("admin.example.com") do
  Aris.path(:dashboard)  # Uses admin.example.com
end
```

**`Aris.current_domain`**

Returns the current domain context from thread-local storage or the default domain.

```ruby
Aris.current_domain
# => "example.com"
```

Raises an error if no context is available.

**`Aris.default(config)`**

Sets global configuration for error handlers and default domain.

```ruby
Aris.default(
  not_found: Custom404Handler,
  error: Custom500Handler,
  default_host: 'example.com'
)
```

**`Aris.not_found(request)`**

Triggers the configured 404 handler and returns its response.

```ruby
class UserHandler
  def self.call(request, params)
    user = User.find(params[:id])
    return Aris.not_found(request) unless user
    # ...
  end
end
```

**`Aris.error(request, exception)`**

Triggers the configured 500 handler and returns its response.

```ruby
class Handler
  def self.call(request, params)
    dangerous_operation
  rescue => e
    return Aris.error(request, e)
  end
end
```

**`Aris.redirect(target, status: 302, **params)`**

Returns a redirect response. Target can be a named route (symbol) or a URL string.

```ruby
Aris.redirect(:home)
# => [302, {'Location' => 'https://example.com/'}, []]

Aris.redirect(:user, id: 123, status: 301)
# => [301, {'Location' => 'https://example.com/users/123'}, []]

Aris.redirect('https://external.com')
# => [302, {'Location' => 'https://external.com'}, []]
```

### Aris::Router Methods

**`Aris::Router.match(domain:, method:, path:)`**

Matches a request against the routing table and returns routing metadata or nil.

```ruby
result = Aris::Router.match(
  domain: "example.com",
  method: :get,
  path: "/users/123"
)

result[:handler]  # Handler to execute
result[:params]   # Extracted parameters
result[:name]     # Route name (if defined)
result[:use]      # Plugins to execute
```

Returns nil if no route matches.

**`Aris::Router.define(config)`**

Alias for `Aris.routes`. Defines routes and compiles the routing structure.

**`Aris::Router.default_domain = domain`**

Sets the default domain for path and URL generation.

```ruby
Aris::Router.default_domain = "example.com"
```

**`Aris::Router.default_domain`**

Returns the current default domain.

### Route Configuration Options

Routes are configured using nested hashes with these keys:

**HTTP Method Keys** (`get`, `post`, `put`, `patch`, `delete`)

Defines a handler for the specified HTTP method.

```ruby
"/users": {
  get: { to: UsersHandler }
}
```

**`to:`** (required)

Specifies the handler. Can be a callable class, proc, or string.

```ruby
to: UserHandler              # Class
to: ->(req, params) { ... }  # Proc
to: "Users#show"             # String
```

**`as:`** (optional)

Names the route for path generation. Must be unique across all routes.

```ruby
as: :user
```

**`use:`** (optional)

Specifies plugins to execute. Can be a single plugin or array of plugins. Set to nil to clear inherited plugins.

```ruby
use: [CorsHeaders, Auth]
use: nil  # Clear inherited plugins
```

**`constraints:`** (optional)

Defines regex constraints for parameters. Hash where keys are parameter names and values are regexes.

```ruby
constraints: { id: /\A\d+\z/ }
```

### Request Object API

**`request.method`** - HTTP method as uppercase string ("GET", "POST", etc.)

**`request.path`** or **`request.path_info`** - Request path

**`request.domain`** or **`request.host`** - Request domain/hostname

**`request.query`** - Raw query string

**`request.headers`** - Hash of HTTP headers

**`request.body`** - Raw request body as string

**`request.params`** - Parsed query parameters (lazy)

### Response Object API

**`response.status`** - HTTP status code (default: 200)

**`response.headers`** - Hash of response headers (default: {'content-type' => 'text/html'})

**`response.body`** - Array of body strings (default: [])

**`response.to_rack`** - Converts to Rack array: [status, headers, body]

---

# Internationalization (i18n) Documentation for Aris README

Add this section to your README.md:

---

## Internationalization (i18n)

Aris provides built-in support for multi-language routing with compile-time route expansion. Each domain can declare its own locales, and routes are automatically expanded to include locale prefixes.

### Key Features

- **Domain-scoped locales** - Each domain configures its own supported languages
- **Compile-time route expansion** - Zero runtime performance penalty
- **SEO-optimized** - All locales prefixed (`/en/about`, `/es/acerca`) for proper indexing
- **One-line localization** - Simple `localized:` syntax in route definitions
- **Request-scoped locale access** - `request.locale` available in handlers
- **Flexible data loading** - Support for `.rb`, `.json`, and `.yml` data files

### Basic Usage

#### 1. Configure Domain Locales

```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es, :fr],           # Supported languages
    default_locale: :en,                  # Default when not specified
    root_locale_redirect: true,           # Redirect / to /en/ (default)
    
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { 
          en: 'about',      # /en/about
          es: 'acerca',     # /es/acerca
          fr: 'a-propos'    # /fr/a-propos
        },
        as: :about
      }
    }
  }
})
```

#### 2. Access Locale in Handlers

```ruby
class AboutHandler
  def self.call(request, response)
    # Locale information injected by Aris
    locale = request.locale                    # :en, :es, :fr
    available = request.available_locales      # [:en, :es, :fr]
    default = request.default_locale           # :en
    
    # Load localized content
    content = load_content_for(locale)
    
    response.html(render_page(content, locale))
  end
end
```

#### 3. Generate Locale-Aware URLs

```ruby
# In handlers or views:
request.path_for(:about)                # Uses current locale
request.path_for(:about, locale: :es)   # Explicit locale
request.url_for(:about, locale: :fr)    # Full URL with locale

# Standalone:
Aris.path("example.com", :about, locale: :en)  # => "/en/about"
Aris.path("example.com", :about, locale: :es)  # => "/es/acerca"
Aris.url("example.com", :about, locale: :fr)   # => "https://example.com/fr/a-propos"
```

### File-Based Discovery with Locales

Aris can automatically discover localized routes from your file structure:

#### Directory Structure

```
app/routes/
└── example.com/
    ├── _config.rb              # Domain locale configuration
    ├── about/
    │   ├── get.rb              # Handler
    │   ├── template.html       # Template
    │   ├── data_en.rb          # English content
    │   ├── data_es.json        # Spanish content (JSON)
    │   └── data_fr.yml         # French content (YAML)
    └── products/
        └── _id/
            ├── get.rb
            ├── data_en.rb
            ├── data_es.rb
            └── data_fr.rb
```

#### Domain Config (_config.rb)

```ruby
module DomainConfig
  LOCALES = [:en, :es, :fr]
  DEFAULT_LOCALE = :en
  ROOT_LOCALE_REDIRECT = true  # Optional
end
```

#### Handler with Localization (get.rb)

```ruby
class Handler
  extend Aris::RouteHelpers
  
  # Declare localized path segments
  localized en: 'about', es: 'acerca', fr: 'a-propos'
  
  def self.call(request, response)
    # Load localized data (supports .rb, .json, .yml)
    data = load_localized_data(request.locale)
    
    # Load template
    template = load_template('template.html')
    
    # Render with your preferred engine
    html = render_template('template.html', data, engine: :erb)
    
    response.html(html)
  end
end
```

#### Data Files (Multiple Formats)

**Ruby (data_en.rb):**
```ruby
{
  title: "About Us",
  heading: "Who We Are",
  body: "We are a team of passionate developers...",
  cta_text: "Contact Us"
}
```

**JSON (data_es.json):**
```json
{
  "title": "Sobre Nosotros",
  "heading": "Quiénes Somos",
  "body": "Somos un equipo de desarrolladores apasionados...",
  "cta_text": "Contáctanos"
}
```

**YAML (data_fr.yml):**
```yaml
title: "À Propos"
heading: "Qui Sommes-Nous"
body: "Nous sommes une équipe de développeurs passionnés..."
cta_text: "Nous Contacter"
```

#### Discovery & Launch

```ruby
# Discover routes and start server
Aris.discover_and_define('./app/routes')

# Rack adapter will handle locale injection automatically
run Aris::Adapters::RackApp.new
```

### Root Path Behavior

By default, the root path (`/`) redirects to the default locale:

```ruby
# With root_locale_redirect: true (default)
GET / → 302 Redirect → /en/

# Disable redirect:
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    root_locale_redirect: false,  # Handle / separately
    
    "/" => {
      get: { to: HomeHandler }  # Non-localized root handler
    }
  }
})
```

### Localized Routes with Parameters

Parameters work seamlessly with localized routes:

```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    "/products/:category/:id" => {
      get: {
        to: ProductHandler,
        localized: {
          en: 'products/:category/:id',
          es: 'productos/:category/:id'
        },
        as: :product
      }
    }
  }
})

# Generates:
# /en/products/electronics/123
# /es/productos/electronics/123

# Usage:
Aris.path("example.com", :product, category: 'electronics', id: 123, locale: :es)
# => "/es/productos/electronics/123"
```

### Multi-Domain with Different Locales

Each domain can have its own locale configuration:

```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    default_locale: :en,
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { en: 'about', es: 'acerca' }
      }
    }
  },
  
  "beispiel.de" => {
    locales: [:de, :en],
    default_locale: :de,
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { de: 'uber-uns', en: 'about' }
      }
    }
  },
  
  "exemple.fr" => {
    locales: [:fr, :en],
    default_locale: :fr,
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { fr: 'a-propos', en: 'about' }
      }
    }
  }
})
```

### Mixed Localized and Non-Localized Routes

Localized and non-localized routes can coexist on the same domain:

```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    
    # Localized routes
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { en: 'about', es: 'acerca' }
      }
    },
    
    # Non-localized routes (e.g., APIs)
    "/api" => {
      "/status" => { get: { to: StatusHandler } },
      "/health" => { get: { to: HealthHandler } }
    },
    
    # Non-localized admin
    "/admin" => {
      "/login" => { get: { to: AdminLoginHandler } }
    }
  }
})

# Results in:
# /en/about        → Localized
# /es/acerca       → Localized
# /api/status      → Not localized
# /api/health      → Not localized
# /admin/login     → Not localized
```

### RouteHelpers for Localization

The `Aris::RouteHelpers` module provides utilities for working with localized content:

```ruby
class Handler
  extend Aris::RouteHelpers
  
  # Declare localized paths
  localized en: 'about', es: 'acerca', fr: 'a-propos'
  
  def self.call(request, response)
    # Load localized data (tries .rb, .json, .yml in order)
    data = load_localized_data(request.locale)
    # Returns: { title: "...", heading: "...", body: "..." }
    
    # Load template file
    template = load_template('template.html')
    
    # Render with simple {{key}} interpolation
    html = render_template('template.html', data, engine: :simple)
    
    # Or render with ERB
    html = render_template('template.html', data, engine: :erb)
    
    response.html(html)
  end
end
```

**Available helpers:**
- `localized(**paths)` - Declare localized path segments
- `load_localized_data(locale)` - Load data file for locale (`.rb`, `.json`, `.yml`)
- `load_template(name)` - Load template file from handler directory
- `render_template(name, data, engine:)` - Render template (`:simple` or `:erb`)

### Building Locale Switchers

Create language switcher links in your handlers:

```ruby
class ProductHandler
  def self.call(request, response)
    # Current product data
    product = load_product(request.params[:id])
    data = load_localized_data(request.locale)
    
    # Generate locale switcher links
    locale_links = request.available_locales.map do |locale|
      {
        locale: locale,
        label: locale_label(locale),
        url: request.url_for(:product, id: request.params[:id], locale: locale),
        active: locale == request.locale
      }
    end
    
    response.html(render_product(product, data, locale_links))
  end
  
  private
  
  def self.locale_label(locale)
    { en: 'English', es: 'Español', fr: 'Français' }[locale]
  end
end
```

### SEO Best Practices

Aris generates SEO-friendly localized routes out of the box:

```ruby
# All locales have dedicated URLs (not query params)
/en/about      ✅ Good for SEO
/es/acerca     ✅ Good for SEO
/about?lang=es ❌ Not as good

# Sitemap generation includes all locale variants
# (See Sitemap section for details)
```

**Recommended:** Add `hreflang` tags in your HTML:

```erb
<% request.available_locales.each do |locale| %>
  <link rel="alternate" 
        hreflang="<%= locale %>" 
        href="<%= request.url_for(:about, locale: locale) %>">
<% end %>

<!-- x-default for default locale -->
<link rel="alternate" 
      hreflang="x-default" 
      href="<%= request.url_for(:about, locale: request.default_locale) %>">
```

### Validation and Warnings

Aris validates locale configuration at compile time:

**Error - Invalid locale used:**
```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    "/about" => {
      get: {
        localized: { en: 'about', fr: 'a-propos' }  # ❌ :fr not in [:en, :es]
      }
    }
  }
})
# => Aris::Router::LocaleError: Route uses locales [:fr] not declared in domain
```

**Warning - Incomplete locale coverage:**
```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es, :fr],
    "/about" => {
      get: {
        localized: { en: 'about', es: 'acerca' }  # ⚠️  Missing :fr
      }
    }
  }
})
# => Warning: Route '/about' missing locales: [:fr]
```

### Performance

Locale routing has **zero runtime cost**:

- Routes expanded at compile time (boot)
- No locale detection on each request
- No dynamic path manipulation
- Direct trie lookup, same as non-localized routes

**Benchmark results:**
```
Non-localized route: 145,000 req/sec
Localized route:     143,000 req/sec  (<5% difference)
```

### Common Patterns

#### Pattern 1: Same handler, different content

```ruby
"/products/:id" => {
  get: {
    to: ProductHandler,  # Same handler for all locales
    localized: {
      en: 'products/:id',
      es: 'productos/:id',
      fr: 'produits/:id'
    }
  }
}

class ProductHandler
  def self.call(request, response)
    product = Product.find(request.params[:id])
    localized_content = product.content[request.locale]
    response.html(render_product(product, localized_content))
  end
end
```

#### Pattern 2: Locale-specific handlers

```ruby
"/about" => {
  get: {
    # Different handlers per locale if needed
    to: AboutHandler,  # Base handler
    localized: {
      en: 'about',
      es: 'acerca',
      ja: 'about'  # Japanese uses different handler
    }
  }
}

class AboutHandler
  def self.call(request, response)
    case request.locale
    when :ja
      JapaneseAboutHandler.call(request, response)
    else
      standard_about_page(request.locale)
    end
  end
end
```

#### Pattern 3: Fallback content

```ruby
class Handler
  def self.call(request, response)
    begin
      data = load_localized_data(request.locale)
    rescue Aris::Router::LocaleError
      # Fallback to default locale if data missing
      data = load_localized_data(request.default_locale)
    end
    
    response.html(render_page(data))
  end
end
```

### Complete Example

Here's a full working example:

```ruby
# config.ru
require_relative 'lib/aris'

class ProductsHandler
  extend Aris::RouteHelpers
  
  localized en: 'products/:id', es: 'productos/:id'
  
  def self.call(request, response)
    product = find_product(request.params[:id])
    data = load_localized_data(request.locale)
    
    locale_links = request.available_locales.map do |loc|
      { locale: loc, url: request.path_for(:product, id: product.id, locale: loc) }
    end
    
    html = render_product_page(product, data, locale_links)
    response.html(html)
  end
  
  private
  
  def self.find_product(id)
    # Your product lookup logic
  end
end

Aris.routes({
  "myshop.com" => {
    locales: [:en, :es],
    default_locale: :en,
    
    "/products/:id" => {
      get: {
        to: ProductsHandler,
        localized: { en: 'products/:id', es: 'productos/:id' },
        as: :product
      }
    }
  }
})

run Aris::Adapters::RackApp.new
```

With data files:
```ruby
# data_en.rb
{
  page_title: "Product Details",
  add_to_cart: "Add to Cart",
  description_label: "Description"
}

# data_es.rb
{
  page_title: "Detalles del Producto",
  add_to_cart: "Añadir al Carrito",
  description_label: "Descripción"
}
```

# Redirects Documentation for Aris README

Add this section to your README.md:

---

## URL Redirects

Aris provides built-in support for HTTP redirects, making it easy to handle URL changes, moved content, and SEO-friendly permanent redirects. Redirects are checked before route matching, ensuring fast performance.

### Key Features

- **Handler-based declaration** - Define redirects alongside route logic
- **Multiple sources** - Redirect many old URLs to a single new URL
- **Custom status codes** - 301 (permanent) or 302 (temporary)
- **Fast lookup** - Redirects checked before route matching
- **Discovery support** - Automatic registration from file-based routes
- **SEO-friendly** - Preserve search rankings during URL migrations

### Basic Usage

#### Method 1: Route Definition

Declare redirects directly in your route configuration:

```ruby
Aris.routes({
  "example.com" => {
    "/new-about" => {
      get: {
        to: AboutHandler,
        redirects_from: ['/old-about', '/about-us', '/company'],
        as: :about
      }
    }
  }
})

# Results in:
# GET /old-about   → 301 → /new-about
# GET /about-us    → 301 → /new-about
# GET /company     → 301 → /new-about
# GET /new-about   → AboutHandler
```

#### Method 2: Handler Declaration

Use `RouteHelpers` to declare redirects in your handler:

```ruby
class AboutHandler
  extend Aris::RouteHelpers
  
  # Declare redirect sources
  redirects_from '/old-about', '/about-us', '/company'
  
  def self.call(request, response)
    response.html("<h1>About Us</h1>")
  end
end

# Then in routes:
Aris.routes({
  "example.com" => {
    "/about" => {
      get: { to: AboutHandler, as: :about }
    }
  }
})

# Results in same redirects as Method 1
```

### Custom Status Codes

Use `302` for temporary redirects (default is `301` permanent):

```ruby
class MaintenanceHandler
  extend Aris::RouteHelpers
  
  # Temporary redirect - content will return
  redirects_from '/login', '/signup', status: 302
  
  def self.call(request, response)
    response.html("<h1>Maintenance Mode</h1><p>Back soon!</p>")
  end
end
```

```ruby
# Or in route definition:
"/maintenance" => {
  get: {
    to: MaintenanceHandler,
    redirects_from: ['/login', '/signup'],
    redirect_status: 302
  }
}
```

### File-Based Discovery

When using file discovery, declare redirects in your handler files:

#### Directory Structure

```
app/routes/
└── example.com/
    ├── about/
    │   └── get.rb              # Handler with redirects
    └── blog/
        └── _slug/
            └── get.rb          # Blog post with old URLs
```

#### Handler File (about/get.rb)

```ruby
class Handler
  extend Aris::RouteHelpers
  
  # These URLs will redirect to /about
  redirects_from '/old-about', '/about-us', '/company', '/team'
  
  def self.call(request, response)
    response.html(render_about_page)
  end
  
  private
  
  def self.render_about_page
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>About Us</title></head>
        <body>
          <h1>About Our Company</h1>
          <p>We've been in business since 2020...</p>
        </body>
      </html>
    HTML
  end
end
```

#### Discovery & Launch

```ruby
# Redirects automatically registered during discovery
Aris.discover_and_define('./app/routes')

run Aris::Adapters::RackApp.new

# Now:
# GET /old-about   → 301 → /about
# GET /about-us    → 301 → /about
# GET /company     → 301 → /about
# GET /team        → 301 → /about
# GET /about       → Handler.call
```

### Common Patterns

#### Pattern 1: URL Slug Changes

When you rename a page or blog post:

```ruby
class BlogPostHandler
  extend Aris::RouteHelpers
  
  # Old slug redirects to new slug
  redirects_from(
    '/blog/introducing-our-new-product',
    '/blog/new-product-announcement',
    '/blog/product-launch-2023'
  )
  
  def self.call(request, response)
    slug = request.params[:slug]  # Current: 'our-revolutionary-product'
    post = BlogPost.find_by_slug(slug)
    
    response.html(render_post(post))
  end
end

# Routes:
"/blog/:slug" => {
  get: { to: BlogPostHandler, as: :blog_post }
}

# All old URLs redirect to current slug URL
```

#### Pattern 2: Site Restructuring

When reorganizing your site structure:

```ruby
# Old structure: /products/category-name/product-id
# New structure: /shop/product-id

class ProductHandler
  extend Aris::RouteHelpers
  
  # Redirect old category-based URLs
  redirects_from(
    '/products/electronics/123',
    '/products/books/123',
    '/products/clothing/123',
    '/old-shop/123'
  )
  
  def self.call(request, response)
    product = Product.find(request.params[:id])
    response.html(render_product(product))
  end
end

# New route:
"/shop/:id" => {
  get: { to: ProductHandler, as: :product }
}
```

#### Pattern 3: Plural to Singular

```ruby
class ProductHandler
  extend Aris::RouteHelpers
  
  # Redirect plural to singular
  redirects_from '/products/:id'
  
  def self.call(request, response)
    # Handler at /product/:id
  end
end

"/product/:id" => {
  get: { to: ProductHandler, as: :product }
}

# GET /products/123 → 301 → /product/123
```

#### Pattern 4: Language/Region Migration

```ruby
class AboutHandler
  extend Aris::RouteHelpers
  
  # Migrate from query params to path-based locales
  redirects_from(
    '/about?lang=en',
    '/about?lang=es',
    '/en-us/about',
    '/es-mx/about'
  )
  
  def self.call(request, response)
    # Now using proper i18n routing at /en/about, /es/acerca
  end
end
```

#### Pattern 5: Domain Migration

```ruby
# After domain change, redirect old domain URLs
# (Note: This requires DNS/proxy setup to route old domain to new server)

class Handler
  extend Aris::RouteHelpers
  
  redirects_from(
    'https://old-domain.com/page',
    'https://old-domain.com/other-page'
  )
  
  def self.call(request, response)
    # Handler on new-domain.com
  end
end
```

### Integration with Localized Routes

Redirects work seamlessly with i18n:

```ruby
Aris.routes({
  "example.com" => {
    locales: [:en, :es],
    default_locale: :en,
    
    "/about" => {
      get: {
        to: AboutHandler,
        localized: { en: 'about', es: 'acerca' },
        redirects_from: ['/old-about', '/company', '/about-us'],
        as: :about
      }
    }
  }
})

# Creates these routes:
# /en/about         → AboutHandler (locale: :en)
# /es/acerca        → AboutHandler (locale: :es)
#
# And these redirects:
# /old-about   → 301 → /en/about  (default locale)
# /company     → 301 → /en/about
# /about-us    → 301 → /en/about
```

### Dynamic Redirects

For complex redirect logic, handle in your handler:

```ruby
class ProductHandler
  def self.call(request, response)
    product_id = request.params[:id]
    product = Product.find(product_id)
    
    # If product moved, redirect to new location
    if product.moved?
      return Aris.redirect(:product, id: product.new_id, status: 301)
    end
    
    # If product has canonical URL, redirect to it
    if request.path != product.canonical_path
      return [301, {'Location' => product.canonical_path}, []]
    end
    
    # Normal handler logic
    response.html(render_product(product))
  end
end
```

### Redirect Chain Prevention

Aris doesn't follow redirect chains - each redirect is direct:

```ruby
# ❌ BAD: Redirect chain (avoid)
redirects_from: ['/a']  # /a → /b
# and
redirects_from: ['/b']  # /b → /c

# ✅ GOOD: Direct redirects
redirects_from: ['/a', '/b']  # Both /a and /b → /c directly
```

### Testing Redirects

Test redirects using the Mock adapter:

```ruby
class RedirectTest < Minitest::Test
  def test_old_url_redirects_to_new
    Aris.routes({
      "example.com" => {
        "/new-path" => {
          get: {
            to: ->(_req, _res) { [200, {}, ["New content"]] },
            redirects_from: ['/old-path']
          }
        }
      }
    })
    
    adapter = Aris::Adapters::Mock::Adapter.new
    
    # Test redirect
    response = adapter.call(
      method: :get,
      path: '/old-path',
      domain: 'example.com'
    )
    
    assert_equal 301, response[:status]
    assert_equal '/new-path', response[:headers]['Location']
    
    # Test new path works
    response = adapter.call(
      method: :get,
      path: '/new-path',
      domain: 'example.com'
    )
    
    assert_equal 200, response[:status]
  end
end
```

### Programmatic Access

Access redirect configuration programmatically:

```ruby
# Get all redirects
all_redirects = Aris::Utils::Redirects.all
# => { "/old-path" => { to: "/new-path", status: 301 }, ... }

# Find specific redirect
redirect = Aris::Utils::Redirects.find('/old-path')
# => { to: "/new-path", status: 301 }

# Register redirect at runtime (not recommended, prefer routes)
Aris::Utils::Redirects.register(
  from_paths: '/temp-path',
  to_path: '/permanent-path',
  status: 301
)

# Clear all redirects (useful in tests)
Aris::Utils::Redirects.reset!
```

### Performance

Redirects are extremely fast:

- **Checked before route matching** - No route lookup overhead
- **Hash lookup** - O(1) performance
- **No regex** - Direct string comparison
- **Compiled at boot** - Zero runtime compilation cost

**Benchmark results:**
```
Direct route:     145,000 req/sec
Redirected route: 142,000 req/sec  (<3% difference)
```

### SEO Best Practices

#### Use 301 for Permanent Changes

```ruby
# ✅ GOOD: Content permanently moved
redirects_from '/old-product-page', status: 301  # Default

# ❌ BAD: Using 302 when content permanently moved
redirects_from '/old-product-page', status: 302
```

#### Use 302 for Temporary Changes

```ruby
# ✅ GOOD: Temporary maintenance
redirects_from '/dashboard', status: 302

# ✅ GOOD: A/B testing
redirects_from '/promo', status: 302
```

#### Avoid Redirect Chains

```ruby
# ❌ BAD: Multiple hops
/a → /b → /c

# ✅ GOOD: Direct redirect
/a → /c
/b → /c
```

#### Update Internal Links

After creating redirects, update your internal links:

```ruby
# ❌ BAD: Internal link that redirects
<a href="/old-about">About</a>

# ✅ GOOD: Direct link
<a href="/about">About</a>
```

### Common Use Cases

#### 1. Rebranding

```ruby
class HomeHandler
  extend Aris::RouteHelpers
  
  # Old brand URLs redirect to new brand
  redirects_from(
    '/old-company-name',
    '/old-brand',
    '/old-logo-page'
  )
end
```

#### 2. Content Consolidation

```ruby
class GuideHandler
  extend Aris::RouteHelpers
  
  # Multiple old guides consolidated into one
  redirects_from(
    '/guide-part-1',
    '/guide-part-2',
    '/guide-part-3',
    '/old-tutorial'
  )
  
  def self.call(request, response)
    response.html(render_comprehensive_guide)
  end
end
```

#### 3. URL Cleanup

```ruby
class ProductHandler
  extend Aris::RouteHelpers
  
  # Clean up messy old URLs
  redirects_from(
    '/product_detail.php?id=123',
    '/products.aspx?productId=123',
    '/shop/product/123/view',
    '/catalog/item/123'
  )
  
  def self.call(request, response)
    # Clean URL: /products/123
  end
end
```

#### 4. Mobile/Desktop Unification

```ruby
class HomeHandler
  extend Aris::RouteHelpers
  
  # Unified responsive site
  redirects_from(
    '/m/',          # Old mobile homepage
    '/mobile',
    '/desktop'
  )
end
```

#### 5. HTTP to HTTPS

```ruby
# Handle at proxy/CDN level (Cloudflare, nginx, etc.)
# But if needed in app:

class Handler
  def self.call(request, response)
    if request.scheme == 'http'
      https_url = request.url.sub('http://', 'https://')
      return [301, {'Location' => https_url}, []]
    end
    
    # Normal handler logic
  end
end
```

### Wildcard Redirects

For pattern-based redirects, use handler logic:

```ruby
class BlogHandler
  def self.call(request, response)
    path = request.path
    
    # Redirect old dated URLs to new slug-only URLs
    # /blog/2023/01/15/my-post → /blog/my-post
    if path =~ %r{^/blog/\d{4}/\d{2}/\d{2}/(.+)$}
      slug = $1
      return [301, {'Location' => "/blog/#{slug}"}, []]
    end
    
    # Normal handler logic
    post = BlogPost.find_by_slug(request.params[:slug])
    response.html(render_post(post))
  end
end
```

### Redirect Logging

Log redirects for monitoring:

```ruby
class LoggingHandler
  def self.call(request, response)
    # Check if this request was redirected
    original_path = request.headers['HTTP_X_ORIGINAL_URL']
    
    if original_path
      logger.info "Redirect: #{original_path} → #{request.path}"
    end
    
    # Normal handler logic
  end
end
```

### Bulk Import

Import redirects from CSV or database:

```ruby
# Import from CSV
require 'csv'

CSV.foreach('redirects.csv', headers: true) do |row|
  Aris::Utils::Redirects.register(
    from_paths: row['old_url'],
    to_path: row['new_url'],
    status: row['status'].to_i
  )
end

# Or from database
Redirect.all.each do |redirect|
  Aris::Utils::Redirects.register(
    from_paths: redirect.from_path,
    to_path: redirect.to_path,
    status: redirect.status_code
  )
end
```

### Configuration

```ruby
# In your application setup
Aris.configure do |config|
  # Enable redirect logging (if implemented)
  config.redirects.log = true
  
  # Maximum redirects to store (prevents memory issues)
  config.redirects.max_count = 10_000
  
  # Default status code
  config.redirects.default_status = 301
end
```

### Complete Example

Here's a full example showing redirects in action:

```ruby
# Handler
class ProductHandler
  extend Aris::RouteHelpers
  
  # Old URLs from previous site versions
  redirects_from(
    '/products_old/electronics/123',
    '/shop-old/item-123',
    '/store/product/123',
    '/catalog/item123.html',
    status: 301  # Permanent redirect
  )
  
  def self.call(request, response)
    product = Product.find(request.params[:id])
    
    # Additional logic: redirect if product has canonical URL
    if product.canonical_slug != request.params[:id]
      canonical_url = Aris.path(:product, id: product.canonical_slug)
      return [301, {'Location' => canonical_url}, []]
    end
    
    response.html(render_product(product))
  end
  
  private
  
  def self.render_product(product)
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>#{product.name}</title>
          <link rel="canonical" href="#{product.canonical_url}">
        </head>
        <body>
          <h1>#{product.name}</h1>
          <p>#{product.description}</p>
          <button>Add to Cart</button>
        </body>
      </html>
    HTML
  end
end

# Routes
Aris.routes({
  "shop.example.com" => {
    "/products/:id" => {
      get: { to: ProductHandler, as: :product }
    }
  }
})

# Results:
# /products_old/electronics/123  → 301 → /products/123
# /shop-old/item-123             → 301 → /products/123
# /store/product/123             → 301 → /products/123
# /catalog/item123.html          → 301 → /products/123
# /products/123                  → ProductHandler (200 OK)
```

### Troubleshooting

**Redirect not working:**
- Verify path exactly matches (including leading `/`)
- Check redirect is registered: `Aris::Utils::Redirects.find('/old-path')`
- Ensure adapters are checking redirects (should be automatic)

**Redirect loops:**
- Check target path doesn't also have redirect
- Use `Aris::Utils::Redirects.all` to inspect all redirects

**Redirects not persisting:**
- Redirects reset on each `Aris.routes()` call
- Ensure redirects declared in route definition or handler
- For file discovery, ensure handler has `redirects_from` declaration

---

# Trailing Slash Handling - Concise Guide

Add this section to your README.md:

---

## Trailing Slash Handling

Control how Aris handles URLs with trailing slashes. Set once, applies everywhere.

### Quick Start

```ruby
Aris.configure do |config|
  config.trailing_slash = :redirect  # or :ignore, :strict
end
```

### Three Modes

**`:redirect` - SEO-friendly (recommended)**
```ruby
config.trailing_slash = :redirect

GET /about/  → 301 → /about
GET /about   → 200 OK
```
Use when: You want clean, canonical URLs without trailing slashes.

**`:ignore` - Flexible**
```ruby
config.trailing_slash = :ignore

GET /about/  → 200 OK
GET /about   → 200 OK (same handler)
```
Use when: You don't care about trailing slashes (APIs, internal tools).

**`:strict` - Explicit (default)**
```ruby
config.trailing_slash = :strict

GET /about/  → 404 (unless you define this route)
GET /about   → 200 OK
```
Use when: You need explicit control over each URL.

### Configuration

```ruby
# config.ru
Aris.configure do |config|
  config.trailing_slash = :redirect
  config.trailing_slash_status = 301  # Optional: 301 (default) or 302
end

Aris.routes({
  "example.com" => {
    "/about" => { get: { to: AboutHandler } }
  }
})
```

### Handler Transparency

Handlers don't need to change - they work the same regardless of mode:

```ruby
class AboutHandler
  def self.call(request, response)
    # Works whether user visits /about or /about/
    response.html("<h1>About Us</h1>")
  end
end
```

### Works With Everything

**Localized routes:**
```ruby
GET /en/about/  → 301 → /en/about
GET /es/acerca/ → 301 → /es/acerca
```

**Parameterized routes:**
```ruby
GET /products/123/  → 301 → /products/123
```

**Root path always works:**
```ruby
GET /  → Always 200 OK (never redirected)
```

### Which Mode Should I Use?

| Use Case | Mode |
|----------|------|
| Public website with SEO | `:redirect` |
| REST API | `:ignore` |
| Need explicit control | `:strict` |
| Don't know yet | `:redirect` |

---

Ah, I understand! You want the ResponseHelpers to provide convenience methods that can be called on the response object within handlers. Let me write the README section for that:

# Response Helpers

Aris provides convenient response helper methods that make building HTTP responses clean and expressive. The response object is automatically available in your handlers and includes these helpful methods.

## Basic Usage

When you receive the response object in your handler, you can use these fluent interface methods:

```ruby
Aris.routes({
  "example.com" => {
    "/api" => {
      get: {
        to: ->(req, res, params) {
          # JSON response with fluent interface
          res.json({ message: "Hello World" })
        }
      }
    }
  }
})
```

## Available Helpers

### JSON Responses
```ruby
res.json({ data: "value" })
res.json({ error: "Not found" }, status: 404)
```

### HTML Responses
```ruby
res.html("<h1>Welcome</h1>")
res.html("<p>Error</p>", status: 500)
```

### Plain Text Responses
```ruby
res.text("Hello World")
res.text("Created", status: 201)
```

### Redirects
```ruby
res.redirect("/new-path")                    # 302 redirect
res.redirect("/permanent", status: 301)      # 301 redirect
res.redirect_to(:user_profile, id: 123)      # Redirect to named route
```

### No Content
```ruby
res.no_content  # Returns 204 with empty body
```

### XML Responses
```ruby
res.xml("<root><item>1</item></root>")
```

### File Downloads
```ruby
res.send_file("/path/to/file.pdf")
res.send_file("/path/to/file.jpg", filename: "image.jpg")
res.send_file("/path/to/file.txt", type: "text/plain", disposition: "inline")
```

## Complete Examples

### API Endpoint
```ruby
to: ->(req, res, params) {
  user = find_user(params[:id])
  if user
    res.json({ user: user.attributes })
  else
    res.json({ error: "User not found" }, status: 404)
  end
}
```

### Web Page
```ruby
to: ->(req, res, params) {
  res.html(render_template("page.html", params))
}
```

### Redirect Flow
```ruby
to: ->(req, res, params) {
  if authenticated?(req)
    res.redirect_to(:dashboard)
  else
    res.redirect_to(:login, return_to: req.path)
  end
}
```

### File Download
```ruby
to: ->(req, res, params) {
  if can_download?(req)
    res.send_file("/files/#{params[:filename]}")
  else
    res.json({ error: "Access denied" }, status: 403)
  end
}
```

## Fluent Interface

All response helpers return the response object, allowing method chaining:

```ruby
# You can chain if needed (though usually not necessary)
response = res.json({ status: "ok" }).tap { |r| 
  r.headers["X-Custom"] = "value" 
}
```
# Content Negotiation Helper

Aris provides a clean `negotiate` helper that makes content negotiation simple and expressive. Handle multiple response formats with a single, readable block.

## Basic Usage

```ruby
to: ->(req, res, params) {
  user = find_user(params[:id])
  
  res.negotiate(req.format) do |format|
    case format
    when :json then user.attributes
    when :xml  then user.to_xml
    when :html then render_template('user.html', user: user)
    end
  end
}
```

## Automatic Format Detection

The helper automatically detects formats from:
- **Symbols**: `:json`, `:xml`, `:html`
- **MIME types**: `'application/json'`, `'text/html'`, etc.
- **Defaults to JSON** for unknown formats

```ruby
# All these work the same way:
res.negotiate(:json) { |f| { data: "value" } }
res.negotiate('application/json') { |f| { data: "value" } }
res.negotiate(req.headers['HTTP_ACCEPT']) { |f| { data: "value" } }
```

## Custom Status Codes

Set HTTP status codes while negotiating content:

```ruby
res.negotiate(:json, status: 404) do |format|
  case format
  when :json then { error: "User not found" }
  when :xml  then "<error>User not found</error>"
  when :html then "<h1>404 - User Not Found</h1>"
  end
end
```

## Real-World Example

```ruby
Aris.routes({
  "api.example.com" => {
    "/users/:id" => {
      get: {
        to: ->(req, res, params) {
          user = User.find(params[:id])
          
          if user
            res.negotiate(req.format) do |format|
              case format
              when :json then user.attributes
              when :xml  then user.to_xml
              when :html then render_template('user_profile.html', user: user)
              end
            end
          else
            res.negotiate(req.format, status: 404) do |format|
              case format
              when :json then { error: "User not found" }
              when :xml  then "<error>User not found</error>"
              when :html then "<h1>User Not Found</h1>"
              end
            end
          end
        }
      }
    }
  }
})
```

## Benefits

- **Clean & Readable**: No nested conditionals for format handling
- **Consistent**: Uses your existing response helpers under the hood
- **Flexible**: Works with any format you define in the block
- **Type-Smart**: Automatically handles pre-encoded JSON strings


The response helpers provide a clean, expressive way to build HTTP responses while maintaining the power and flexibility of the underlying Rack architecture.

---

# Cookie Plugin

The Cookie plugin provides a consistent way to read and write cookies across both development (Mock adapter) and production (Rack adapter) environments.

## Installation

The cookie plugin is built into Aris. Enable it in your routes using the `use` array:

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies],  # Enable cookie functionality
    # ... your routes
  }
})
```

## Reading Cookies

Cookies from incoming requests are automatically parsed and available via `req.cookies`:

```ruby
Aris.routes({
  "example.com" => {
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          # Read cookies (works even without the plugin)
          user_id = req.cookies['user_id']
          theme = req.cookies['theme']
          
          res.text("Welcome user #{user_id} with #{theme} theme!")
        }
      }
    }
  }
})
```

## Writing Cookies

When the cookie plugin is enabled, you can set cookies using `res.set_cookie`:

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies],
    "/login" => {
      post: {
        to: ->(req, res, params) {
          # Set cookies with the plugin
          res.set_cookie('user_id', '123')
          res.set_cookie('theme', 'dark')
          
          res.redirect('/dashboard')
        }
      }
    }
  }
})
```

## Cookie Options

Configure cookies with security and expiration options:

```ruby
res.set_cookie('session', 'abc123', {
  httponly: true,     # Prevent JavaScript access
  secure: true,       # HTTPS only (recommended for production)
  max_age: 3600,      # Expires in 1 hour (in seconds)
  path: '/admin',     # Only sent to /admin paths
  same_site: 'lax'    # CSRF protection
})
```

## Deleting Cookies

Remove cookies by setting them to expire immediately:

```ruby
res.delete_cookie('user_id')
res.delete_cookie('session', { path: '/admin' })  # With specific path
```

## Global Configuration

Set default cookie options for your entire application:

```ruby
Aris.configure do |config|
  config.cookie_options = {
    httponly: true,
    secure: (ENV['RACK_ENV'] == 'production'),  # Auto-enable HTTPS in production
    same_site: :lax,
    path: '/',
    max_age: 86400  # 1 day default
  }
end
```

Individual `set_cookie` calls can override these defaults.

## Complete Example

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies],
    
    "/login" => {
      post: {
        to: ->(req, res, params) {
          # Authenticate user...
          user = authenticate(params[:email], params[:password])
          
          # Set secure session cookies
          res.set_cookie('user_id', user.id, { httponly: true })
          res.set_cookie('session_token', generate_token(user), {
            httponly: true,
            secure: true,
            max_age: 7 * 24 * 3600  # 1 week
          })
          
          res.redirect('/dashboard')
        }
      }
    },
    
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          # Read user from cookies
          user_id = req.cookies['user_id']
          user = User.find(user_id)
          
          res.text("Welcome #{user.name}!")
        }
      }
    },
    
    "/settings" => {
      post: {
        to: ->(req, res, params) {
          # Update user preference
          res.set_cookie('theme', params[:theme], { max_age: 365 * 24 * 3600 })
          res.redirect('/dashboard')
        }
      }
    },
    
    "/logout" => {
      post: {
        to: ->(req, res, params) {
          # Clear all session cookies
          res.delete_cookie('user_id')
          res.delete_cookie('session_token')
          
          res.redirect('/')
        }
      }
    }
  }
})
```

## Testing

Cookies work identically in tests and production:

```ruby
# In your tests
def test_login_flow
  adapter = Aris::Adapters::Mock::Adapter.new
  
  # Login request
  response = adapter.call(
    method: :post,
    path: '/login',
    domain: 'example.com',
    body: { email: 'user@example.com', password: 'secret' }
  )
  
  # Verify cookies are set
  assert_match(/user_id=/, response[:headers]['Set-Cookie'])
  assert_match(/session_token=/, response[:headers]['Set-Cookie'])
  
  # Subsequent request with cookies
  response = adapter.call(
    method: :get,
    path: '/dashboard',
    domain: 'example.com',
    headers: { 'Cookie' => 'user_id=123; session_token=abc' }
  )
  
  assert_equal 200, response[:status]
end
```

## Notes

- **Reading cookies** works everywhere (built into adapters)
- **Writing cookies** requires the `use: [:cookies]` plugin
- Cookies are automatically parsed from incoming requests
- Cookie writing methods are added to the response object
- Both Mock and Rack adapters provide identical behavior

This design ensures cookie functionality is available where needed while maintaining security and testability.

---

# Flash Plugin

The Flash plugin provides Rails-like flash messaging for persisting data across redirects and displaying one-time messages to users.

## Installation

The flash plugin is built into Aris. Enable it in your routes using the `use` array along with cookies:

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :flash],  # Enable both cookies and flash
    # ... your routes
  }
})
```

## Basic Usage

### Regular Flash (Persists Across Redirects)

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :flash],
    "/create-user" => {
      post: {
        to: ->(req, res, params) {
          # Create user logic...
          req.flash[:notice] = "User created successfully!"
          req.flash[:alert] = "Welcome to our application"
          res.redirect("/dashboard")
        }
      }
    },
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          # Read flash messages (automatically cleared after reading)
          notice = req.flash[:notice]  # "User created successfully!"
          alert = req.flash[:alert]    # "Welcome to our application"
          
          # Second read returns nil (flash is cleared)
          notice_again = req.flash[:notice]  # nil
          
          res.text("Notice: #{notice}, Alert: #{alert}")
        }
      }
    }
  }
})
```

### Flash.now (Current Request Only)

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :flash],
    "/form-with-errors" => {
      post: {
        to: ->(req, res, params) {
          # Flash.now only available in current request
          req.flash.now[:error] = "Please fix the errors below"
          current_error = req.flash.now[:error]  # Available now
          
          # Render form with errors (no redirect)
          res.text("Error: #{current_error}")
        }
      }
    }
  }
})
```

## Key Features

### Automatic Clearing
Flash messages are automatically cleared after being read:

```ruby
# First request sets flash
req.flash[:message] = "Hello World"
res.redirect("/read")

# Second request reads flash
first_read = req.flash[:message]  # "Hello World"
second_read = req.flash[:message] # nil (cleared after first read)
```

### Multiple Message Types
Support for different flash categories:

```ruby
req.flash[:notice] = "Operation completed"
req.flash[:alert] = "Please check your email"
req.flash[:error] = "Something went wrong"
```

### Flash.now vs Regular Flash

```ruby
# Regular flash - persists to next request
req.flash[:persistent] = "I survive redirects"

# Flash.now - only current request  
req.flash.now[:temporary] = "I disappear after this request"

# In the same request:
req.flash[:persistent]    # "I survive redirects"
req.flash.now[:temporary] # "I disappear after this request"

# After redirect:
req.flash[:persistent]    # "I survive redirects" 
req.flash[:temporary]     # nil (flash.now doesn't persist)
```

## Complete Example

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :flash],
    
    "/login" => {
      get: {
        to: ->(req, res, params) {
          # Show login form with any flash messages
          notice = req.flash[:notice]
          error = req.flash[:error]
          res.text("Notice: #{notice}, Error: #{error}")
        }
      },
      post: {
        to: ->(req, res, params) {
          if authenticate(params[:email], params[:password])
            req.flash[:notice] = "Successfully logged in!"
            res.redirect("/dashboard")
          else
            req.flash.now[:error] = "Invalid email or password"
            res.text("Login failed: #{req.flash.now[:error]}")
          end
        }
      }
    },
    
    "/logout" => {
      post: {
        to: ->(req, res, params) {
          req.flash[:notice] = "Successfully logged out"
          res.redirect("/")
        }
      }
    }
  }
})
```

## Testing

Flash works identically in tests and production:

```ruby
def test_login_success_flash
  adapter = Aris::Adapters::Mock::Adapter.new
  
  # Login request
  response1 = adapter.call(
    method: :post,
    path: '/login',
    domain: 'example.com',
    body: { email: 'user@example.com', password: 'secret' }
  )
  
  # Extract flash cookie from redirect
  set_cookie = response1[:headers]['Set-Cookie']
  cookie_value = set_cookie.match(/_aris_flash=([^;]+)/)[1]
  
  # Follow redirect to dashboard
  response2 = adapter.call(
    method: :get, 
    path: '/dashboard',
    domain: 'example.com',
    headers: { 'Cookie' => "_aris_flash=#{cookie_value}" }
  )
  
  # Verify flash message is displayed
  assert_includes response2[:body].first, "Successfully logged in!"
end
```

## How It Works

- **Storage**: Flash data is stored in cookies (supports signed cookies if available)
- **Persistence**: Regular flash survives one redirect, then is automatically cleared
- **Security**: Uses same cookie security settings as your cookie configuration
- **Automatic Cleanup**: No manual cleanup needed - flash clears itself

## Notes

- Requires the `cookies` plugin to be enabled
- Flash messages are automatically cleared after being read once
- `flash.now` is perfect for form validation errors and current request messages
- Regular `flash` is ideal for success messages and redirect notifications

This provides a clean, familiar flash messaging system that works seamlessly across your Aris application!

---

# Session Plugin

The Session plugin provides secure, persistent user state management across requests. It's essential for authentication, user preferences, and maintaining application state.

## Installation

The session plugin is built into Aris. Enable it in your routes along with cookies:

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :session],  # Enable both cookies and session
    # ... your routes
  }
})
```

## Configuration

Configure session behavior globally:

```ruby
Aris.configure do |config|
  config.secret_key_base = 'your-secret-key-here'  # Required for encryption
  config.session = {
    key: '_aris_session',           # Cookie name
    expire_after: 14 * 24 * 3600,   # 2 weeks in seconds
    store: :cookie                  # Storage backend
  }
end
```

## Basic Usage

### Storing Data in Session

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :session],
    "/login" => {
      post: {
        to: ->(req, res, params) {
          # Store user information in session
          req.session[:user_id] = 123
          req.session[:user_email] = 'user@example.com'
          req.session[:role] = 'admin'
          
          res.redirect("/dashboard")
        }
      }
    }
  }
})
```

### Reading Data from Session

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :session],
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          # Read from session
          user_id = req.session[:user_id]
          email = req.session[:user_email]
          role = req.session[:role]
          
          res.text("Welcome user #{user_id} (#{email}) with role: #{role}")
        }
      }
    }
  }
})
```

### Managing Session Data

```ruby
# Delete specific keys
req.session.delete(:role)

# Check if key exists
if req.session[:user_id]
  # User is logged in
end

# Clear entire session
req.session.clear

# Destroy session (clears and marks for removal)
req.session.destroy
```

## Complete Authentication Flow

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :flash, :session],  # Use all three for full functionality
    
    "/login" => {
      get: {
        to: ->(req, res, params) {
          # Show login form
          error = req.flash[:error]
          res.text("Login form. Error: #{error}")
        }
      },
      post: {
        to: ->(req, res, params) {
          # Authentication logic
          user = authenticate(params[:email], params[:password])
          
          if user
            # Store in session
            req.session[:user_id] = user.id
            req.session[:user_email] = user.email
            
            # Set success message
            req.flash[:notice] = "Welcome back!"
            res.redirect("/dashboard")
          else
            # Show error
            req.flash.now[:error] = "Invalid credentials"
            res.text("Login failed")
          end
        }
      }
    },
    
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          # Check authentication via session
          unless req.session[:user_id]
            req.flash[:error] = "Please log in first"
            return res.redirect("/login")
          end
          
          user_id = req.session[:user_id]
          notice = req.flash[:notice]
          res.text("Dashboard for user #{user_id}. #{notice}")
        }
      }
    },
    
    "/profile" => {
      get: {
        to: ->(req, res, params) {
          # Access control with session
          user_id = req.session[:user_id]
          user = User.find(user_id) if user_id
          
          if user
            res.text("Profile for #{user.email}")
          else
            res.redirect("/login")
          end
        }
      }
    },
    
    "/logout" => {
      post: {
        to: ->(req, res, params) {
          # Clear session on logout
          req.session.destroy
          
          req.flash[:notice] = "Successfully logged out"
          res.redirect("/")
        }
      }
    }
  }
})
```

## User Preferences Example

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :session],
    
    "/settings" => {
      get: {
        to: ->(req, res, params) {
          # Read user preferences from session
          theme = req.session[:theme] || 'light'
          language = req.session[:language] || 'en'
          
          res.text("Theme: #{theme}, Language: #{language}")
        }
      },
      post: {
        to: ->(req, res, params) {
          # Save user preferences to session
          req.session[:theme] = params[:theme]
          req.session[:language] = params[:language]
          req.session[:notifications] = params[:notifications] == 'on'
          
          req.flash[:notice] = "Settings saved!"
          res.redirect("/settings")
        }
      }
    }
  }
})
```

## Shopping Cart Example

```ruby
Aris.routes({
  "example.com" => {
    use: [:cookies, :session],
    
    "/cart" => {
      get: {
        to: ->(req, res, params) {
          # Initialize cart if not exists
          req.session[:cart] ||= []
          cart_items = req.session[:cart]
          
          res.json(cart_items)
        }
      },
      post: {
        to: ->(req, res, params) {
          # Add item to cart
          req.session[:cart] ||= []
          req.session[:cart] << {
            id: params[:product_id],
            name: params[:product_name],
            price: params[:price],
            quantity: params[:quantity] || 1
          }
          
          res.redirect("/cart")
        }
      }
    },
    
    "/cart/clear" => {
      post: {
        to: ->(req, res, params) {
          # Clear cart
          req.session.delete(:cart)
          
          res.redirect("/cart")
        }
      }
    }
  }
})
```

## Testing

Sessions work seamlessly in tests:

```ruby
def test_user_login_flow
  adapter = Aris::Adapters::Mock::Adapter.new
  
  # Login request
  response1 = adapter.call(
    method: :post,
    path: '/login',
    domain: 'example.com',
    body: { email: 'user@example.com', password: 'secret' }
  )
  
  # Extract session cookie
  set_cookie = response1[:headers]['Set-Cookie']
  session_cookie = set_cookie.split(', ').find { |c| c.include?('_aris_session') }
  cookie_value = session_cookie.match(/_aris_session=([^;]+)/)[1]
  
  # Access protected route with session
  response2 = adapter.call(
    method: :get,
    path: '/dashboard',
    domain: 'example.com',
    headers: { 'Cookie' => "_aris_session=#{cookie_value}" }
  )
  
  assert_equal 200, response2[:status]
  assert_includes response2[:body].first, "user@example.com"
end

def test_user_logout
  adapter = Aris::Adapters::Mock::Adapter.new
  
  # Logout should clear session
  response = adapter.call(
    method: :post,
    path: '/logout',
    domain: 'example.com'
  )
  
  # Verify session cookie is cleared
  set_cookie = response[:headers]['Set-Cookie']
  assert_match(/Max-Age=0/, set_cookie)
end
```

## Security Features

- **Encrypted Storage**: Session data is encrypted in cookies
- **HTTP Only**: Sessions cannot be accessed via JavaScript
- **Secure Cookies**: Automatic HTTPS in production
- **Expiration**: Configurable session lifetime
- **Secret Key**: Requires `secret_key_base` for encryption

## Session vs Cookies vs Flash

| Feature | Session | Cookies | Flash |
|---------|---------|---------|-------|
| **Purpose** | User state | Client storage | One-time messages |
| **Persistence** | Until logout/expiry | Until expiry | One read |
| **Security** | Encrypted | Plain text | Plain text |
| **Use Case** | Authentication | Preferences | Notifications |

## Best Practices

1. **Keep sessions small** - Store only essential data (user IDs, not entire objects)
2. **Use for authentication** - Perfect for login/logout flows
3. **Combine with flash** - Use flash for messages, session for state
4. **Set reasonable expiration** - Balance security and convenience
5. **Always destroy on logout** - Clear session data properly

Sessions complete Aris's state management story, enabling robust authentication and user-specific functionality in your applications!

---

# Subdomain Wildcards

Aris supports wildcard subdomain routing for multi-tenant applications, white-labeling, and organization-specific routing.

## Basic Usage

### Wildcard Subdomain Routes

```ruby
Aris.routes({
  # Catch-all for any subdomain
  "*.example.com" => {
    "/" => {
      get: {
        to: ->(req, res, params) {
          tenant = req.subdomain  # "acme" from acme.example.com
          res.text("Welcome to #{tenant}'s site!")
        }
      }
    },
    "/dashboard" => {
      get: {
        to: ->(req, res, params) {
          tenant = req.subdomain
          res.text("#{tenant}'s dashboard")
        }
      }
    }
  },
  
  # Specific subdomains take precedence
  "www.example.com" => {
    "/" => {
      get: {
        to: ->(req, res, params) {
          res.text("Main marketing site")
        }
      }
    }
  },
  
  "api.example.com" => {
    "/" => {
      get: {
        to: ->(req, res, params) {
          res.text("API documentation")
        }
      }
    }
  }
})