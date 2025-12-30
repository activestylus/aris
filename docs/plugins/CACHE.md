# Response Caching Plugin

In-memory response caching for GET requests. Dramatically improves performance by serving cached responses without executing handlers or database queries.

## Installation

```ruby
require 'aris/plugins/cache'
```

## Basic Usage

```ruby
cache = Aris::Plugins::Cache.build(ttl: 60)  # Cache for 60 seconds

Aris.routes({
  "api.example.com": {
    use: [cache],
    "/users": { get: { to: UsersHandler } }
  }
})
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ttl` | Integer | `60` | Time-to-live in seconds |
| `store` | Hash | `{}` | Custom cache store (in-memory hash by default) |
| `skip_paths` | Array | `[]` | Regex patterns of paths to skip caching |
| `cache_control` | String | `nil` | Cache-Control header value to set |

## How It Works

1. **Cache Miss (First Request)**
   - Handler executes normally
   - Response cached with TTL
   - `X-Cache: MISS` header added

2. **Cache Hit (Subsequent Requests)**
   - Cached response returned instantly
   - Handler NOT executed
   - `X-Cache: HIT` header added

3. **Cache Expiry**
   - After TTL expires, cache miss occurs
   - Handler executes, new response cached

## Examples

### Basic Caching

```ruby
cache = Aris::Plugins::Cache.build(ttl: 300)  # 5 minutes

Aris.routes({
  "api.example.com": {
    use: [cache],
    "/products": { get: { to: ProductsHandler } }
  }
})

# First request: Handler executes, 100ms
# Second request: Cached, 1ms (100x faster!)
```

### Different TTLs per Route

```ruby
short_cache = Aris::Plugins::Cache.build(ttl: 60)      # 1 minute
long_cache = Aris::Plugins::Cache.build(ttl: 3600)    # 1 hour

Aris.routes({
  "api.example.com": {
    "/users": { 
      use: [short_cache],
      get: { to: UsersHandler }
    },
    "/static": { 
      use: [long_cache],
      get: { to: StaticHandler }
    }
  }
})
```

### Skip Certain Paths

```ruby
cache = Aris::Plugins::Cache.build(
  ttl: 60,
  skip_paths: [
    /^\/admin/,      # Skip /admin/*
    /^\/health/,     # Skip health checks
    /^\/auth/        # Skip auth endpoints
  ]
)

Aris.routes({
  "api.example.com": {
    use: [cache],
    "/users": { get: { to: UsersHandler } },      # Cached
    "/admin": { get: { to: AdminHandler } },      # NOT cached
    "/health": { get: { to: HealthHandler } }     # NOT cached
  }
})
```

### Custom Cache-Control Headers

```ruby
cache = Aris::Plugins::Cache.build(
  ttl: 300,
  cache_control: 'public, max-age=300, s-maxage=600'
)

# Response includes:
# Cache-Control: public, max-age=300, s-maxage=600
# (CDNs and browsers can cache too)
```

### Bypass Cache with Header

```ruby
# Client sends:
# Cache-Control: no-cache

# Cache is bypassed, fresh response generated
```

## Cache Key Generation

Keys are generated from:
- Domain
- Path
- Query string

```ruby
# Different cache entries:
GET /users            → cache_key_1
GET /users?page=2     → cache_key_2
GET /products         → cache_key_3
```

## Production Tips

### 1. Choose TTL Wisely

**Highly dynamic data:**
```ruby
cache = Cache.build(ttl: 10)  # 10 seconds
```

**Frequently changing:**
```ruby
cache = Cache.build(ttl: 60)  # 1 minute
```

**Rarely changing:**
```ruby
cache = Cache.build(ttl: 3600)  # 1 hour
```

**Static data:**
```ruby
cache = Cache.build(ttl: 86400)  # 24 hours
```

### 2. Use Redis for Multi-Server

In-memory cache doesn't work across servers. Use Redis:

```ruby
require 'redis'

redis_store = Redis.new(url: ENV['REDIS_URL'])

cache = Aris::Plugins::Cache.build(
  ttl: 300,
  store: redis_store  # Shared across all servers
)
```

**Note:** Current implementation uses Hash. You'd need to adapt it for Redis compatibility.

### 3. Skip Non-Cacheable Endpoints

```ruby
cache = Cache.build(
  ttl: 60,
  skip_paths: [
    /^\/admin/,          # Admin panels
    /^\/auth/,           # Authentication
    /^\/checkout/,       # Checkout flows
    /^\/cart/,           # Shopping carts
    /\/me$/,             # User-specific
    /^\/health/,         # Health checks
    /^\/metrics/         # Monitoring
  ]
)
```

### 4. Combine with ETag

```ruby
etag = Aris::Plugins::ETag.build
cache = Aris::Plugins::Cache.build(ttl: 300)

Aris.routes({
  "api.example.com": {
    use: [cache, etag],  # Cache first, then ETag
    "/data": { get: { to: DataHandler } }
  }
})

# Flow:
# 1. Check cache (X-Cache: HIT)
# 2. Check ETag (304 Not Modified)
# 3. Bandwidth saved twice!
```

### 5. Monitor Cache Hit Rate

```ruby
class CacheMetrics
  def self.call(request, response)
    cache_status = response.headers['X-Cache']
    
    StatsD.increment('cache.hits') if cache_status == 'HIT'
    StatsD.increment('cache.misses') if cache_status == 'MISS'
    
    nil
  end
end

# Target: 60-80% hit rate for cacheable endpoints
```

### 6. Vary by User

User-specific data needs per-user cache keys:

```ruby
class UserCache
  def initialize(**config)
    @cache = Aris::Plugins::Cache.build(**config)
  end
  
  def call(request, response)
    # Add user ID to cache key
    user_id = request.instance_variable_get(:@current_user)&.id
    request.instance_variable_set(:@cache_suffix, user_id)
    
    @cache.call(request, response)
  end
end
```

### 7. Clear Cache on Updates

```ruby
class UsersHandler
  def self.update(request, params)
    user = User.update(params[:id], request.json_body)
    
    # Clear cache for this user
    cache.clear!  # Or selective clear
    
    { user: user }
  end
end
```

## Performance Benchmarks

**Example API endpoint:**
- Without cache: 100ms (database query + JSON serialization)
- With cache: 1-2ms (memory lookup)
- **50-100x speedup**

**Typical cache hit rates:**
- Public APIs: 70-90%
- Authenticated APIs: 40-60%
- Admin panels: 10-30%

## Common Patterns

### Tiered Caching

```ruby
fast_cache = Cache.build(ttl: 30)      # 30s for hot data
slow_cache = Cache.build(ttl: 3600)    # 1h for cold data

Aris.routes({
  "api.example.com": {
    "/trending": { use: [fast_cache], get: { to: TrendingHandler } },
    "/archive": { use: [slow_cache], get: { to: ArchiveHandler } }
  }
})
```

### Cache Warming

```ruby
# On deploy/startup
cache = Cache.build(ttl: 300)

popular_paths = ['/products', '/categories', '/home']
popular_paths.each do |path|
  # Make request to warm cache
  app.call(build_env(path))
end
```

### Conditional Caching

```ruby
class SmartCache
  def call(request, response)
    # Only cache successful responses
    return nil unless response.status == 200
    
    # Only cache small responses
    return nil if response.body.join.bytesize > 100_000
    
    # Proceed with caching
    @cache.call(request, response)
  end
end
```

## Notes

- Only caches GET requests (POST/PUT/PATCH/DELETE not cached)
- Only caches 200 OK responses
- In-memory by default (not shared across servers)
- Thread-safe (uses Mutex)
- Respects `Cache-Control: no-cache` from client
- Cache key includes domain, path, and query string
- Expired entries are removed on access

## Limitations

1. **In-memory only** - Doesn't persist across restarts
2. **No cache size limit** - Could grow unbounded (add LRU if needed)
3. **No cache invalidation** - Only expires via TTL
4. **Single-server** - Doesn't work across multiple servers

For production with multiple servers, integrate Redis or Memcached.

## Troubleshooting

**Cache not working?**
- Verify request method is GET
- Check response status is 200
- Ensure path isn't in `skip_paths`
- Look for `X-Cache` header in response

**Low cache hit rate?**
- Check if data changes frequently
- Verify TTL isn't too short
- Look for query string variations
- Monitor cache expiry rate

**Memory issues?**
- Reduce TTL
- Add cache size limits
- Use Redis instead of in-memory
- Skip large responses