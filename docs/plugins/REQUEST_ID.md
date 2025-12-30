# Request ID Plugin

Generates unique request IDs for distributed tracing and log correlation. Essential for debugging in production environments.

## Installation

```ruby
require 'aris/plugins/request_id'
```

## Basic Usage

```ruby
request_id = Aris::Plugins::RequestId.build

Aris.routes({
  "api.example.com": {
    use: [request_id],  # Apply to all routes
    "/users": { get: { to: UsersHandler } }
  }
})
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `header_name` | String | `'X-Request-ID'` | HTTP header name for request ID |
| `generator` | Proc | `-> { SecureRandom.uuid }` | Custom ID generator function |

## How It Works

1. **Check for existing ID**: If request has `X-Request-ID` header (from proxy/load balancer), use it
2. **Generate new ID**: If none provided, generate UUID
3. **Store on request**: Handlers can access via `@request_id` instance variable
4. **Return in response**: Set `X-Request-ID` header in response

## Examples

### Default Configuration

```ruby
request_id = Aris::Plugins::RequestId.build

# Request without ID:
# Response: X-Request-ID: 550e8400-e29b-41d4-a716-446655440000

# Request with ID:
# Request: X-Request-ID: existing-id-123
# Response: X-Request-ID: existing-id-123 (preserved)
```

### Custom Header Name

```ruby
request_id = Aris::Plugins::RequestId.build(
  header_name: 'X-Trace-ID'
)

# Response will have X-Trace-ID instead of X-Request-ID
```

### Custom Generator

```ruby
# Sequential IDs
counter = 0
request_id = Aris::Plugins::RequestId.build(
  generator: -> { "REQ-#{counter += 1}" }
)

# Timestamp-based IDs
request_id = Aris::Plugins::RequestId.build(
  generator: -> { "#{Time.now.to_i}-#{SecureRandom.hex(4)}" }
)

# Short IDs
request_id = Aris::Plugins::RequestId.build(
  generator: -> { SecureRandom.hex(8) }  # 16 characters
)
```

### Accessing Request ID in Handlers

```ruby
class UsersHandler
  def self.call(request, params)
    request_id = request.instance_variable_get(:@request_id)
    
    # Use in logging
    logger.info("Processing user request", request_id: request_id)
    
    # Return in response
    {
      users: User.all,
      request_id: request_id
    }
  end
end
```

### With Logging Plugin

```ruby
request_id = Aris::Plugins::RequestId.build
logger = Aris::Plugins::RequestLogger.build(format: :json)

Aris.routes({
  "api.example.com": {
    use: [request_id, logger],  # Request ID first
    "/users": { get: { to: UsersHandler } }
  }
})

# Logs will include request_id for correlation
```

## Production Tips

### 1. Plugin Order (Critical)

Place **first** in plugin chain:

```ruby
Aris.routes({
  "api.example.com": {
    use: [
      request_id,       # ← FIRST - generate ID
      bearer_auth,      # Use request_id in auth logs
      json_parser,      # Use request_id in parser logs
      request_logger    # Log request_id
    ]
  }
})
```

### 2. Structured Logging

Combine with logging plugin for correlation:

```ruby
class CustomLogger
  def self.call(request, response)
    request_id = request.instance_variable_get(:@request_id)
    
    logger.info({
      request_id: request_id,
      method: request.method,
      path: request.path,
      timestamp: Time.now.iso8601
    }.to_json)
    
    nil
  end
end
```

### 3. Load Balancer Integration

Preserve IDs from upstream:

```ruby
# AWS ALB sends X-Amzn-Trace-Id
request_id = Aris::Plugins::RequestId.build(
  header_name: 'X-Amzn-Trace-Id'
)

# Or check multiple headers
class SmartRequestId
  def self.call(request, response)
    request_id = request.headers['HTTP_X_AMZN_TRACE_ID'] ||
                 request.headers['HTTP_X_REQUEST_ID'] ||
                 SecureRandom.uuid
    
    request.instance_variable_set(:@request_id, request_id)
    response.headers['X-Request-ID'] = request_id
    
    nil
  end
end
```

### 4. Error Tracking

Include request ID in error responses:

```ruby
class ErrorHandler
  def self.call(request, exception)
    request_id = request.instance_variable_get(:@request_id)
    
    [500, { 'content-type' => 'application/json' }, [
      {
        error: 'Internal Server Error',
        request_id: request_id,
        message: exception.message
      }.to_json
    ]]
  end
end

Aris.default(error: ErrorHandler)
```

### 5. Distributed Tracing

Propagate to downstream services:

```ruby
class ServiceClient
  def self.call_api(request, endpoint)
    request_id = request.instance_variable_get(:@request_id)
    
    # Pass to downstream service
    HTTParty.get(
      "https://api.example.com#{endpoint}",
      headers: { 'X-Request-ID' => request_id }
    )
  end
end
```

### 6. Database Query Tagging

Tag queries with request ID:

```ruby
class UsersHandler
  def self.call(request, params)
    request_id = request.instance_variable_get(:@request_id)
    
    # Tag ActiveRecord queries
    ActiveRecord::Base.connection.execute(
      "SET application_name = 'request_#{request_id}'"
    )
    
    User.all
  end
end
```

### 7. APM Integration

Send to monitoring services:

```ruby
class APMHandler
  def self.call(request, params)
    request_id = request.instance_variable_get(:@request_id)
    
    # NewRelic
    NewRelic::Agent.add_custom_attributes(request_id: request_id)
    
    # Datadog
    Datadog::Tracing.active_span&.set_tag('request.id', request_id)
    
    # Your logic here
  end
end
```

## Common Patterns

### Multi-Service Architecture

```ruby
# Service A (Frontend API)
request_id = Aris::Plugins::RequestId.build

# Service B (Backend API)
# Receives X-Request-ID from Service A
request_id = Aris::Plugins::RequestId.build  # Preserves existing ID

# All logs across services have same request_id for correlation
```

### Request ID in Sidekiq Jobs

```ruby
class ProcessOrderJob
  def perform(order_id, request_id)
    logger.tagged(request_id) do
      logger.info "Processing order #{order_id}"
      # Process order
    end
  end
end

class OrdersHandler
  def self.call(request, params)
    request_id = request.instance_variable_get(:@request_id)
    
    # Enqueue with request_id
    ProcessOrderJob.perform_async(params[:id], request_id)
    
    { status: 'processing', request_id: request_id }
  end
end
```

### Client Response Headers

```ruby
# Clients can use request_id for support tickets
# Response: X-Request-ID: 550e8400-e29b-41d4-a716-446655440000

# User: "Error with request ID: 550e8400-..."
# Support: grep logs for 550e8400-... → full request trace
```

## ID Format Options

**UUID (default):**
```ruby
# 550e8400-e29b-41d4-a716-446655440000
generator: -> { SecureRandom.uuid }
```

**Short hex:**
```ruby
# a3f2bc9e
generator: -> { SecureRandom.hex(4) }
```

**Timestamp + random:**
```ruby
# 1634567890-a3f2bc9e
generator: -> { "#{Time.now.to_i}-#{SecureRandom.hex(4)}" }
```

**Sequential (testing only):**
```ruby
# REQ-1, REQ-2, REQ-3...
counter = 0
generator: -> { "REQ-#{counter += 1}" }
```

## Benchmarks

**Performance impact:**
- UUID generation: ~0.01ms
- Header setting: ~0.001ms
- Total overhead: <0.02ms per request

Negligible impact, essential value.

## Notes

- Thread-safe (UUID generation is thread-safe)
- Preserves IDs from load balancers/proxies
- Available to all downstream handlers
- Always returned in response headers
- Compatible with AWS ALB, Nginx, HAProxy trace IDs

## Troubleshooting

**Request ID not showing up?**
- Check plugin is in `use:` array
- Verify plugin runs before logging/handlers
- Confirm response headers are visible

**Different IDs in logs vs response?**
- Ensure request_id plugin runs first
- Check no other plugin overwrites header

**Load balancer ID not preserved?**
- Check header name matches (`X-Request-ID` vs `X-Amzn-Trace-Id`)
- Verify load balancer is forwarding header
```