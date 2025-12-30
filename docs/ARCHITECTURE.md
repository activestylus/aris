**Create: `docs/ARCHITECTURE.md`**

```markdown
# Architecture

## 30-Second Overview

```
Router matches route → PipelineRunner executes plugins + handler → Adapter formats output
```

**Key idea:** Router core knows nothing about servers. Adapters translate between servers and the universal Request/Response interface.

## The Stack

```
┌─────────────────────────────────────────┐
│  Adapter (Rack, Agoo, Mock, etc.)       │  ← Server-specific I/O
├─────────────────────────────────────────┤
│  PipelineRunner                         │  ← Executes plugins → handler
├─────────────────────────────────────────┤
│  Router (Trie-based matching)           │  ← domain/path/method → route
└─────────────────────────────────────────┘
```

## Core Components

### Router (`lib/aris/core.rb`)
- Trie-based route matching
- Compiles at startup (zero runtime parsing)
- Handles: domains, path params, wildcards, constraints
- Resolves plugin symbols → classes at compile time

### PipelineRunner (`lib/aris/pipeline_runner.rb`)
- Server-agnostic execution
- Runs plugin chain, calls handler
- Returns result (Response/Array/Hash/String)

### Adapters (`lib/aris/adapters/*`)
- Translate server input → Request
- Call PipelineRunner
- Format result → server output
- Manage thread-local context

### Plugins (`lib/aris/plugins/*`)
- Contract: `call(request, response) → nil or response`
- Return `nil` = continue, return `response` = halt
- Work with ANY adapter (zero coupling)

## Request Flow

```
1. HTTP request arrives
2. Adapter creates Request object
3. Router.match(domain, method, path) → route
4. PipelineRunner.call(request, route, response)
   ├─ Execute each plugin in route[:use]
   ├─ If plugin returns response → halt, return it
   └─ Execute handler with params
5. Adapter formats result for server
```

## Design Decisions

**Hash-based config everywhere**
```ruby
plugin.build(token: 'secret')  # NOT plugin.build { |c| c.token = 'secret' }
```

**No magic symbols/tags**
```ruby
use: [:csrf, bearer_auth]  # :csrf from registry, bearer_auth is instance
```

**Compile-time resolution**
```ruby
Router.define(config)  # Symbols resolve to classes here, not per-request
```

**Thread-local domain**
```ruby
Thread.current[:aris_current_domain]  # Enables path helpers without passing domain
```

**Request mutation via ivars**
```ruby
request.instance_variable_set(:@current_user, user)  # Plugins attach data
handler.instance_variable_get(:@current_user)         # Handlers read it
```

## Plugin Contract

```ruby
class MyPlugin
  def self.call(request, response)
    # Read: request.method, request.path, request.headers, etc.
    # Write: response.status, response.headers, response.body
    
    return response if should_halt  # Stop pipeline
    nil                             # Continue
  end
  
  def self.build(**config)
    new(**config)  # Config via keyword args
  end
end
```

## Adapter Contract

**Request must implement:**
- `method`, `path`, `domain`, `query`, `headers`, `body`, `params`
- Aliases: `request_method`, `path_info`, `host`
- Mutable: `json_body` accessor (for JSON plugin)

**Response must have:**
- `status`, `headers`, `body` (all read/write)

**Adapter must:**
1. Create Request from server input
2. Set `Thread.current[:aris_current_domain]`
3. Call `Router.match` → get route
4. Call `PipelineRunner.call(request, route, response)`
5. Format result for server
6. Clean up thread-local in `ensure` block

## File Structure

```
lib/aris/
  core.rb              # Router + trie matching
  pipeline_runner.rb   # Plugin/handler execution
  plugins.rb           # Plugin registry
  adapters/
    rack/
      adapter.rb       # Rack server integration
      request.rb       # Rack env → Request
      response.rb      # Response object
    mock/              # Testing adapter (no server)
      ...
  plugins/
    csrf.rb            # CSRF protection
    json.rb            # JSON parser
    bearer_auth.rb     # Auth plugins
    ...
```

## Performance Notes

- Trie lookup: O(path segments)
- Plugin resolution: compile-time (zero runtime cost)
- No regex on hot path (only in constraints)
- Request caching: parse headers/params once
- Thread-local overhead: ~1-2 allocations/request

## Testing Strategy

- **Rack tests** (90%): Full integration via Rack adapter
- **Mock adapter** (10%): Proves abstraction works
- **Contract tests**: Verify Request/Response interface

All plugins tested once via Rack. Adapter tests are minimal.

## Why This Design?

**Problem:** Ruby servers (Rack, Agoo, Iodine) have different APIs  
**Solution:** Adapter pattern + PipelineRunner abstraction  
**Result:** Write plugins once, work everywhere

**Tradeoff:** Slight abstraction overhead vs. massive flexibility gain

## Next Steps

- **Using Rack?** Use `Aris::Adapters::Rack::Adapter` (works now)
- **Other server?** Build adapter (see `docs/ADAPTERS.md`)
- **New plugin?** Just implement `call(request, response)` contract

That's it. Simple, fast, composable. 🚀
```

**Create: `docs/README.md`** (index for docs)

```markdown
# Documentation

## Quick Links

- **[Architecture](ARCHITECTURE.md)** - How Aris Router works (5 min read)
- **[Adapters](ADAPTERS.md)** - Building custom server adapters (10 min read)

## Philosophy

- Zero magic
- Hash-based config
- Plugin composition
- Server agnostic
- Performance first

## Getting Started

```ruby
require 'aris'

Aris.routes({
  "example.com": {
    use: [:json, :csrf],  # Plugin chain
    "/api/users/:id": {
      get: { to: UsersHandler, as: :user }
    }
  }
})

app = Aris::Adapters::Rack::Adapter.new
```

Done.
```

Run tests to confirm nothing broke:
```bash
ruby test/run_all_tests.rb
```
