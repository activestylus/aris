# ETag / Conditional Requests Plugin

Implements HTTP ETags for efficient caching with 304 Not Modified responses. Reduces bandwidth and improves performance for unchanged resources.

## Installation

```ruby
require 'aris/plugins/etag'
```

## Basic Usage

```ruby
etag = Aris::Plugins::ETag.build

Aris.routes({
  "api.example.com": {
    use: [etag],  # Apply to all routes
    "/users": { get: { to: UsersHandler } }
  }
})
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache_control` | String | `'max-age=0, private, must-revalidate'` | Cache-Control header value |
| `strong` | Boolean | `true` | Use strong ETags (`"abc123"`) vs weak (`W/"abc123"`) |

## How It Works

1. **First request**: Generate MD5 hash of response body, return as ETag header
2. **Subsequent requests**: Client sends `If-None-Match: "hash"`
3. **If match**: Return `304 Not Modified` with empty body (saves bandwidth)
4. **If no match**: Return `200 OK` with full body and new ETag

## Examples

### Default Configuration

```ruby
etag = Aris::Plugins::ETag.build

# First request:
# Response: 200 OK
# ETag: "5d41402abc4b2a76b9719d911017c592"
# Body: "Hello World"

# Second request with If-None-Match: "5d41402abc4b2a76b9719d911017c592"
# Response: 304 Not Modified
# ETag: "5d41402abc4b2a76b9719d911017c592"
# Body: (empty)
```

### Public Caching

```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'public, max-age=3600'  # 1 hour cache
)

# CDNs and browsers can cache for 1 hour
```

### Private Caching

```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'private, max-age=300'  # 5 minute private cache
)

# Only browser caches, not CDNs
```

### Weak ETags

```ruby
etag = Aris::Plugins::ETag.build(
  strong: false  # Use weak ETags
)

# Response: ETag: W/"5d41402abc4b2a76b9719d911017c592"
# Weak ETags allow byte-for-byte differences (compression, whitespace)
```

### No Caching

```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'no-cache, no-store, must-revalidate'
)

# ETags still generated but cache discouraged
```

### Per-Route Configuration

```ruby
public_etag = Aris::Plugins::ETag.build(
  cache_control: 'public, max-age=86400'  # 24 hours
)

private_etag = Aris::Plugins::ETag.build(
  cache_control: 'private, max-age=300'   # 5 minutes
)

Aris.routes({
  "api.example.com": {
    "/public/data": {
      use: [public_etag],
      get: { to: PublicDataHandler }
    },
    "/user/profile": {
      use: [private_etag],
      get: { to: ProfileHandler }
    }
  }
})
```

## Strong vs Weak ETags

**Strong ETags** (`"abc123"`):
- Byte-for-byte identical content
- Use for: APIs, exact data matching
- Default behavior

**Weak ETags** (`W/"abc123"`):
- Semantically equivalent content
- Allows minor differences (compression, formatting)
- Use for: HTML pages, compressed responses

```ruby
# Strong (default)
etag = Aris::Plugins::ETag.build(strong: true)

# Weak
etag = Aris::Plugins::ETag.build(strong: false)
```

## Production Tips

### 1. Cache-Control Strategy

**Static assets (images, JS, CSS):**
```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'public, max-age=31536000, immutable'  # 1 year
)
```

**API responses (frequently changing):**
```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'private, max-age=60'  # 1 minute
)
```

**User-specific data:**
```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'private, max-age=300'  # 5 minutes
)
```

**Real-time data:**
```ruby
etag = Aris::Plugins::ETag.build(
  cache_control: 'no-cache, must-revalidate'  # Validate every time
)
```

### 2. Plugin Ordering

Place **after** compression, **before** logging:

```ruby
Aris.routes({
  "api.example.com": {
    use: [
      bearer_auth,      # Authenticate
      compression,      # Compress response
      etag,            # ← Generate ETag (from compressed body)
      request_logger    # Log (sees 304s)
    ]
  }
})
```

### 3. CDN Compatibility

Most CDNs respect ETags:
```ruby
# Origin generates ETags
etag = Aris::Plugins::ETag.build(
  cache_control: 'public, max-age=3600'
)

# CDN will:
# 1. Cache response with ETag
# 2. Validate with origin using If-None-Match
# 3. Serve from cache on 304
```

### 4. Database-Backed ETags

For better cache invalidation, use timestamps:

```ruby
class UserHandler
  def self.call(request, params)
    user = User.find(params[:id])
    
    # Set custom ETag from updated_at timestamp
    response = Aris::Adapters::Rack::Response.new
    response.headers['ETag'] = %("#{user.updated_at.to_i}")
    response.body = [user.to_json]
    response
  end
end
```

Plugin will respect existing ETags and skip generation.

### 5. Monitoring 304 Responses

Track cache hit rate:
```ruby
# In logs, count 304 vs 200 responses
# High 304 rate = effective caching
# Target: 60-80% 304 rate for cacheable endpoints
```

## Benchmarks

**304 Response Savings:**
- Bandwidth: 95-99% reduction (only headers sent)
- Server CPU: 0% (handler not executed)
- Response time: 10-50ms vs 100-500ms for full response

**Example:**
- Full response: 50KB, 100ms
- 304 response: 500 bytes, 10ms
- 100 requests: 5MB → 50KB saved (99% reduction)

## Notes

- ETags generated using MD5 hash of response body
- Only applies to successful GET/HEAD requests (200 status)
- Does not override existing ETag headers
- Does not override existing Cache-Control headers
- Thread-safe (no shared state)
- Works with compressed responses (generates ETag from compressed body)

## Common Patterns

### Combining with CORS

```ruby
cors = Aris::Plugins::Cors.build(origins: '*')
etag = Aris::Plugins::ETag.build(cache_control: 'public, max-age=600')

Aris.routes({
  "api.example.com": {
    use: [cors, etag],  # CORS first, then ETag
    "/data": { get: { to: DataHandler } }
  }
})
```

### API Versioning

```ruby
v1_etag = Aris::Plugins::ETag.build(cache_control: 'private, max-age=300')
v2_etag = Aris::Plugins::ETag.build(cache_control: 'private, max-age=600')

Aris.routes({
  "api.example.com": {
    "/v1": {
      use: [v1_etag],
      "/users": { get: { to: V1::UsersHandler } }
    },
    "/v2": {
      use: [v2_etag],
      "/users": { get: { to: V2::UsersHandler } }
    }
  }
})
```

## Troubleshooting

**ETags not working?**
- Verify GET request (ETags only for GET/HEAD)
- Check response status is 200
- Confirm client sends `If-None-Match` header

**Always getting 200, never 304?**
- Response body is changing (dynamic content)
- Check for timestamps or random data in response
- Use database-backed ETags for dynamic content

**CDN not caching?**
- Check `Cache-Control` includes `public`
- Verify `max-age` is set
- Add `Vary: Accept-Encoding` if using compression
```