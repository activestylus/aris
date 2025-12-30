# Adapter Architecture

Aris Router uses a **PipelineRunner** abstraction that makes it server-agnostic. The router core handles route matching, while adapters translate between server-specific I/O and the universal `Request`/`Response` interface.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Aris::Router (Core)                     │
│                  Domain/Path/Method Matching                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  Aris::PipelineRunner                       │
│            Executes Plugins → Handler → Response            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐
│  Rack Adapter    │  │  Mock Adapter    │  │  Your Adapter  │
│  (Puma, Falcon)  │  │  (Testing)       │  │  (Agoo, etc)   │
└──────────────────┘  └──────────────────┘  └────────────────┘
```

## Key Concepts

### 1. PipelineRunner (Server-Agnostic Core)

Located in `lib/aris/pipeline_runner.rb`, this module executes the plugin pipeline and handler. It works with ANY adapter that provides a compatible Request/Response.

**Signature:**
```ruby
PipelineRunner.call(request: request, route: route, response: response)
# Returns: Response object, Array, Hash, or String
```

### 2. Adapter Responsibilities

An adapter must:
1. Convert server-specific input → Aris Request
2. Set thread-local domain context
3. Match route via `Router.match`
4. Call `PipelineRunner.call`
5. Format PipelineRunner result → server-specific output
6. Clean up thread-local context

### 3. Request Interface Contract

Any Request class MUST implement these methods:

```ruby
class YourAdapter::Request
  # Required: HTTP method
  def method
    # Return: String (e.g., "GET", "POST")
  end
  
  def request_method
    # Alias for method (some plugins use this)
  end
  
  # Required: Path
  def path
    # Return: String (e.g., "/users/123")
  end
  
  def path_info
    # Alias for path
  end
  
  # Required: Domain/Host
  def domain
    # Return: String (e.g., "example.com")
  end
  
  def host
    # Alias for domain
  end
  
  # Required: Query string
  def query
    # Return: String (e.g., "page=1&limit=10")
  end
  
  # Required: Headers
  def headers
    # Return: Hash with header names as keys
    # Example: { 'HTTP_AUTHORIZATION' => 'Bearer token' }
  end
  
  # Required: Body
  def body
    # Return: String (raw request body)
  end
  
  # Required: Query parameters
  def params
    # Return: Hash of parsed query string
    # Example: { 'page' => '1', 'limit' => '10' }
  end
  
  # Optional but recommended: Struct-like access
  def [](key)
    # Return value for :method, :domain, :path, etc.
  end
  
  # Required: Plugin data attachment
  attr_accessor :json_body  # For JSON parser plugin
  # Plugins may use instance variables like @current_user
end
```

### 4. Response Interface Contract

Any Response class MUST have these attributes:

```ruby
class YourAdapter::Response
  attr_accessor :status   # Integer (e.g., 200, 404)
  attr_accessor :headers  # Hash (e.g., {'content-type' => 'application/json'})
  attr_accessor :body     # Array of strings (e.g., ['Hello'])
  
  def initialize
    @status = 200
    @headers = {'content-type' => 'text/html'}
    @body = []
  end
end
```

## Building a Custom Adapter

### Example: Agoo Adapter

Here's how to create an adapter for Agoo (high-performance Ruby server):

**File Structure:**
```
lib/aris/adapters/agoo/
  adapter.rb
  request.rb
  response.rb
```

**1. Request Implementation (`agoo/request.rb`):**

```ruby
module Aris
  module Adapters
    module Agoo
      class Request
        attr_reader :agoo_request
        attr_accessor :json_body
        
        def initialize(agoo_request)
          @agoo_request = agoo_request
        end
        
        def method
          @agoo_request.request_method
        end
        
        alias_method :request_method, :method
        
        def path
          @agoo_request.path_info
        end
        
        alias_method :path_info, :path
        
        def domain
          @agoo_request.headers['Host'] || 'localhost'
        end
        
        alias_method :host, :domain
        
        def query
          @agoo_request.query_string || ''
        end
        
        def headers
          # Convert Agoo headers to standard format
          @headers ||= @agoo_request.headers.transform_keys do |key|
            "HTTP_#{key.upcase.gsub('-', '_')}"
          end
        end
        
        def body
          @body ||= @agoo_request.body
        end
        
        def params
          @params ||= begin
            return {} if query.empty?
            query.split('&').each_with_object({}) do |pair, hash|
              key, value = pair.split('=')
              hash[key] = value if key
            end
          end
        end
        
        def [](key)
          case key
          when :method then method
          when :domain then domain
          when :path then path
          when :host then host
          else nil
          end
        end
      end
    end
  end
end
```

**2. Response Implementation (`agoo/response.rb`):**

```ruby
module Aris
  module Adapters
    module Agoo
      class Response
        attr_accessor :status, :headers, :body
        
        def initialize
          @status = 200
          @headers = {'content-type' => 'text/html'}
          @body = []
        end
      end
    end
  end
end
```

**3. Adapter Implementation (`agoo/adapter.rb`):**

```ruby
require_relative '../../core'
require_relative '../../pipeline_runner'
require_relative 'request'
require_relative 'response'
require 'json'

module Aris
  module Adapters
    module Agoo
      class Adapter
        def call(agoo_request)
          request = Request.new(agoo_request)
          request_domain = request.host
          Thread.current[:aris_current_domain] = request_domain
          
          begin
            route = Aris::Router.match(
              domain: request_domain,
              method: request.request_method.downcase.to_sym,
              path: request.path_info
            )

            unless route
              return format_agoo_response(Aris.not_found(request))
            end
            
            response = Response.new
            
            # Core execution via PipelineRunner
            result = PipelineRunner.call(
              request: request, 
              route: route, 
              response: response
            )
            
            format_agoo_response(result, response)

          rescue Aris::Router::RouteNotFoundError
            return format_agoo_response(Aris.not_found(request))
          rescue Exception => e
            return format_agoo_response(Aris.error(request, e))
          ensure
            Thread.current[:aris_current_domain] = nil
          end
        end

        private

        def format_agoo_response(result, response = nil)
          case result
          when Response
            # Return Agoo-compatible response
            [result.status, result.headers, result.body]
          when Array
            # Already in [status, headers, body] format
            result
          when Hash
            headers = response ? response.headers.merge({'content-type' => 'application/json'}) : {'content-type' => 'application/json'}
            [200, headers, [result.to_json]]
          else
            headers = response ? response.headers.merge({'content-type' => 'text/plain'}) : {'content-type' => 'text/plain'}
            [200, headers, [result.to_s]]
          end
        end
      end
    end
  end
end
```

**4. Usage:**

```ruby
require 'agoo'
require 'aris'
require 'aris/adapters/agoo/adapter'

# Define routes
Aris.routes({
  "example.com": {
    "/hello": {
      get: { to: ->(req, params) { "Hello from Agoo!" } }
    }
  }
})

# Start Agoo server
Agoo::Server.init(6464, 'root')

handler = Aris::Adapters::Agoo::Adapter.new
Agoo::Server.handle(:GET, '/hello', handler)

Agoo::Server.start
```

## Plugin Compatibility

**The beauty of this architecture:** Plugins work with ANY adapter without modification!

```ruby
# This plugin works with Rack, Agoo, Mock, or any future adapter
bearer_auth = Aris::Plugins::BearerAuth.build(token: 'secret')

Aris.routes({
  "api.example.com": {
    use: [bearer_auth],  # Works everywhere!
    "/data": {
      get: { to: DataHandler }
    }
  }
})
```

### Why Plugins Are Adapter-Agnostic

Plugins only use the **interface contract** methods:
- `request.method` - Works in any adapter
- `request.headers` - Works in any adapter
- `request.body` - Works in any adapter
- `response.status = 401` - Works in any adapter

Example from `BearerAuth` plugin:
```ruby
def call(request, response)
  auth_header = request.headers['HTTP_AUTHORIZATION']  # ← Interface method
  
  if auth_header.nil?
    response.status = 401  # ← Interface method
    return response
  end
  
  # ... validation logic
  nil  # Continue pipeline
end
```

## Testing Your Adapter

### 1. Basic Functionality Test

```ruby
class YourAdapterTest < Minitest::Test
  def test_basic_request
    Aris.routes({
      "test.com": {
        "/hello": { get: { to: ->(req, params) { "Hi!" } } }
      }
    })
    
    adapter = YourAdapter::Adapter.new
    result = adapter.call(your_request_format)
    
    assert_equal 200, result[:status]
  end
end
```

### 2. Plugin Compatibility Test

```ruby
def test_plugin_works
  json_plugin = Aris::Plugins::Json
  
  Aris.routes({
    "test.com": {
      use: [json_plugin],
      "/api": { post: { to: ->(req, params) { req.json_body } } }
    }
  })
  
  adapter = YourAdapter::Adapter.new
  result = adapter.call(
    method: 'POST',
    body: '{"test": true}',
    headers: { 'content-type' => 'application/json' }
  )
  
  # Plugin should have parsed JSON
  assert_includes result[:body].first, 'test'
end
```

## Existing Adapters

### Rack Adapter (Production)
- **Location:** `lib/aris/adapters/rack/`
- **Servers:** Puma, Falcon, Unicorn, Passenger, WEBrick
- **Usage:** `Aris::Adapters::Rack::Adapter.new`

### Mock Adapter (Testing)
- **Location:** `lib/aris/adapters/mock/`
- **Purpose:** Unit testing without server overhead
- **Usage:** `Aris::Adapters::Mock::Adapter.new`

## Performance Considerations

1. **Request Object Caching:** Cache parsed headers, params, body to avoid re-parsing
2. **Thread-Local Cleanup:** ALWAYS clean up `Thread.current[:aris_current_domain]` in ensure block
3. **Minimal Allocations:** Reuse objects where possible in hot paths
4. **Lazy Parsing:** Don't parse body/params until accessed

## Adapter Checklist

When building a new adapter, verify:

- [ ] Request implements all required methods
- [ ] Response implements all required attributes
- [ ] Thread-local domain context is set/cleaned up
- [ ] Error handling (404/500) works
- [ ] Path parameters work (`/users/:id`)
- [ ] Query parameters work (`?page=1`)
- [ ] Request body is accessible
- [ ] Headers are accessible (with HTTP_ prefix convention)
- [ ] Plugins work (test with BearerAuth, Json, CORS)
- [ ] Response formatting handles all types (Response, Array, Hash, String)

## Future Adapter Ideas

- **Iodine:** Native C extension server
- **Falcon:** Async fiber-based server
- **Thin:** EventMachine-based server
- **Direct CGI:** For traditional CGI environments
- **Lambda/Serverless:** AWS Lambda, Google Cloud Functions

## Questions?

The adapter pattern is simple but powerful. If you're building a custom adapter and hit issues, check:
1. Does your Request implement ALL interface methods?
2. Is thread-local context cleaned up?
3. Can you run the Mock adapter tests with your adapter?

Happy adapting! 🚀
```

**Run tests to confirm docs are accurate:**
```bash
ruby test/run_all_tests.rb
```

✅ Once that passes, want me to create a quick `ARCHITECTURE.md` showing the overall system design?