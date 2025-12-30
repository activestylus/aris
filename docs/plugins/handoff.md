# 🎯 Aris Router - Project Handoff Document

## Project Overview

**Aris Router** is a high-performance, minimalist web router for Ruby with a plugin-based middleware system. Design philosophy: **simple, fast, and developer-friendly**.

**Core Principles:**
- Zero magic, explicit routing
- Plugin-based architecture (no policy tag symbols, everything executable)
- Thread-safe, domain-aware routing
- Hash-based configuration everywhere
- Convention: favor hashes over DSLs

---

## Architecture

### Core Components

1. **`Aris::Router`** (`lib/aris/core.rb`)
   - Trie-based route matching
   - Compiles routes at startup (no runtime parsing)
   - Supports domain routing, path parameters, wildcards, constraints
   - Plugin resolution happens at compile time (symbols → classes)

2. **`Aris::Rack`** (`lib/aris/rack.rb`)
   - Rack adapter
   - Executes plugin pipeline
   - Sets thread-local domain context
   - Handles errors (404/500)

3. **`Aris::Request` & `Aris::Response`** (`lib/aris/rack.rb`)
   - Request: immutable wrapper around Rack env
   - Response: mutable object plugins can modify

4. **Plugin System** (`lib/aris/plugins.rb`)
   - Registry maps symbols to plugin classes
   - Plugins must implement `call(request, response)`
   - Return `nil` to continue, return `response` to halt

---

## File Structure

```
lib/
  aris.rb                     # Main entry point, requires everything
  aris/
    core.rb                    # Router implementation
    rack.rb                    # Rack adapter + Request/Response
    plugins.rb                 # Plugin registry
    plugins/
      csrf.rb                  # CSRF protection (2 classes)
      json.rb                  # JSON body parser
      rate_limiter.rb          # Rate limiting (in-memory)
      basic_auth.rb            # HTTP Basic Auth
      bearer_auth.rb           # Bearer token auth
      cors.rb                  # CORS headers

test/
  test_helper.rb               # Test setup, loads aris.rb
  core.rb                      # Router core tests
  errors.rb                    # Error handling tests
  path_helpers.rb              # Path/URL helper tests
  plugins/
    csrf_test.rb
    json_test.rb
    rate_limiter_test.rb
    basic_auth_test.rb
    bearer_auth_test.rb
    cors_test.rb
```

---

## Current State (All Working ✅)

### Router Features
- ✅ Domain-based routing (exact + wildcard)
- ✅ Path matching (literal, params, wildcards)
- ✅ Constraints (regex validation)
- ✅ Named routes
- ✅ Path/URL helpers
- ✅ Plugin inheritance (domain → scope → route)
- ✅ Plugin deduplication
- ✅ Thread-safe context management
- ✅ Custom 404/500 handlers

### Plugins Implemented
- ✅ CSRF (token generation + validation)
- ✅ JSON Parser (POST/PUT/PATCH)
- ✅ Rate Limiter (100 req/60s, in-memory)
- ✅ Basic Auth (username/password or validator)
- ✅ Bearer Auth (token or validator)
- ✅ CORS (origins, methods, credentials, preflight)

### Test Coverage
- ✅ All core router tests passing
- ✅ All plugin tests passing
- ✅ Error handling tests passing
- ✅ Path/URL helper tests passing

---

## Key Code Patterns

### 1. Plugin Contract

```ruby
class MyPlugin
  def self.call(request, response)
    # Inspect request (immutable)
    # Modify response (mutable)
    
    return response if should_halt  # Halt pipeline
    nil  # Continue to next plugin/handler
  end
  
  def self.build(**config)
    new(**config)
  end
end
```

### 2. Plugin Registration

```ruby
# Single plugin
Aris.register_plugin(:my_plugin, plugin_class: MyPlugin)

# Multi-class plugin (like CSRF)
Aris.register_plugin(:csrf,
  generator: CsrfTokenGenerator,
  protection: CsrfProtection
)
```

### 3. Route Definition

```ruby
Aris.routes({
  "example.com": {
    use: [:csrf, bearer_auth],  # Symbols resolve at compile time
    
    "/users/:id": {
      get: { to: UsersHandler, as: :user },
      constraints: { id: /\d+/ }
    },
    
    "/health": {
      use: nil,  # Clear inherited plugins
      get: { to: HealthHandler }
    }
  }
})
```

### 4. Handler Pattern

```ruby
class MyHandler
  def self.call(request, params)
    # Access parsed data
    data = request.json_body
    user = request.instance_variable_get(:@current_user)
    
    # Return formats
    { json: 'response' }  # Auto-converts
    "text response"       # Plain text
    [200, {}, ["body"]]   # Rack array
  end
end
```

### 5. Test Pattern

```ruby
class PluginTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "test.com"
    
    plugin = Aris::Plugins::MyPlugin.build(config: 'value')
    
    Aris.routes({
      "test.com": {
        use: [plugin],
        "/path": { get: { to: Handler } }
      }
    })
    
    @app = Aris::Adapters::RackApp.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_env(path, method: 'GET', **headers)
    {
      'REQUEST_METHOD' => method.to_s.upcase,
      'PATH_INFO' => path,
      'HTTP_HOST' => 'test.com',
      'rack.input' => StringIO.new('')
    }.merge(headers)
  end
end
```

---

## Critical Decisions Made

### 1. No Policy Tags
**Decision:** All items in `use:` must be executable classes. No symbolic tags like `:web`, `:auth`.  
**Reason:** Simpler execution model, no special cases. If you need a tag, make it a plugin.

### 2. Thread-Local Domain Context
**Decision:** Store current domain in `Thread.current[:aris_current_domain]`  
**Reason:** Enables path/URL helpers without passing domain everywhere.  
**Cleanup:** Always clear in Rack ensure block.

### 3. Compile-Time Plugin Resolution
**Decision:** Symbols resolve to classes during `Router.define`, not at runtime.  
**Reason:** Zero runtime overhead, fail-fast on missing plugins.

### 4. Hash-Based Plugin Config
**Decision:** All plugins use `build(**config)` with keyword args.  
**Reason:** Serializable, testable, Ruby idiom.

### 5. In-Memory Rate Limiter
**Decision:** Ship simple in-memory version, document Redis upgrade path.  
**Reason:** Works for single-server, easy to test. Production users can upgrade.

### 6. Request Mutation via Instance Variables
**Decision:** Plugins attach data using `request.instance_variable_set(:@key, value)`  
**Reason:** Clean, low-allocation, handlers access with `instance_variable_get`.

---

## Plugin Roadmap (Priority Order)

### Implemented ✅
- CSRF Protection
- JSON Body Parser  
- Rate Limiter (basic)
- Basic Auth
- Bearer Auth
- CORS

### High Priority (Essential for APIs)
1. **Security Headers** - X-Frame-Options, CSP, etc.
2. **Request Logging** - JSON logs with duration
3. **API Key Auth** - Simpler than Bearer for some use cases

### Medium Priority
4. Response Compression (gzip/brotli)
5. Content Negotiation (JSON/XML)
6. Form Parser (URL-encoded)
7. Multipart Parser (file uploads)
8. ETag/Conditional requests
9. Request ID tracking

### Nice to Have
10. Circuit Breaker
11. Response Caching
12. Webhook Signature Verification
13. JWT Auth
14. OAuth2
15. Health Check endpoint

---

## Known Limitations

1. **Rate Limiter** - In-memory only, won't work across servers
2. **CSRF** - Thread-local storage, single request lifecycle only
3. **No streaming** - JSON parser reads entire body into memory
4. **OPTIONS routes** - Must be explicitly defined for CORS preflight
5. **Basic Auth** - Doesn't support colons in usernames (RFC limitation)

---

## Testing Notes

- Run tests: `ruby -Ilib:test test/core.rb`
- All tests use Minitest
- Test helper at `test/test_helper.rb` loads main lib
- Always clean up thread-local state in `teardown`
- Use `build_env` helper for Rack env construction
- Mock handlers defined inline in test files

---

## Documentation Structure

Each plugin has:
1. **Implementation** - Ruby code with clear comments
2. **Test Suite** - Comprehensive coverage
3. **README** - Basic/Advanced usage, patterns, production tips

Style: Concise, practical examples, minimal edge cases.

---

## Next Steps

1. **Security Headers Plugin** - Easy win, high value
2. **Request Logging Plugin** - Critical for production
3. **Update Main README** - Add plugin examples
4. **Performance Testing** - Benchmark trie matching

---

## Context to Provide New LLM

```
You are continuing development on Aris Router, a minimalist Ruby web router.

Key facts:
- All code in lib/aris/, tests in test/
- Plugin contract: call(request, response) → nil or response
- No policy tags - all use: items must be executable
- Hash-based config everywhere (build(**config))
- Tests use Minitest, all currently passing
- Thread-local domain context (cleanup in teardown!)

Recent work: Built CSRF, JSON, Rate Limit, Basic/Bearer Auth, CORS plugins

Next priority: Security Headers plugin

Load these files for context:
- lib/aris/core.rb (router implementation)
- lib/aris/rack.rb (rack adapter)  
- lib/aris/plugins.rb (registry)
- lib/aris/plugins/cors.rb (latest plugin example)
- test/plugins/cors_test.rb (test pattern)
```

---

**This document captures everything needed to continue development seamlessly.** 🎯