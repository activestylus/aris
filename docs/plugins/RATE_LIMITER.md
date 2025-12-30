# Rate Limiter Plugin

Throttle requests to prevent abuse, brute force attacks, and API overuse.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/rate_limiter'
```

## How It Works

Tracks request counts per key (API key, IP address, user ID) within a time window. Returns **429 Too Many Requests** when limit exceeded.

**Default:** 100 requests per 60 seconds per key.

---

## Basic Usage

### Simple API Rate Limiting

```ruby
Aris.routes({
  "api.example.com": {
    use: [:rate_limit],  # Default: 100 requests/60s
    "/data": { get: { to: DataHandler } }
  }
})
```

Requests include rate limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 47
```

When limit exceeded:
```
HTTP/1.1 429 Too Many Requests
Retry-After: 60
Rate limit exceeded. Try again later.
```

---

## Configuration

Rate limiting keys **default to API key or host**:

```ruby
# Uses HTTP_X_API_KEY header if present, else falls back to HTTP_HOST
request.headers['HTTP_X_API_KEY'] || request.host
```

**For custom configuration**, you need to build a custom instance. The plugin is currently not configurable via symbol registration.

---

## Advanced Usage

### Custom Instance (Not Yet Supported)

The current implementation is fixed at 100 requests per 60 seconds. For production use, you'll want to enhance it:

```ruby
# Future enhancement - custom limits
rate_limit = Aris::Plugins::RateLimiter.build(
  limit: 1000,
  window: 3600,  # 1 hour
  key_extractor: ->(request) {
    # Rate limit by authenticated user
    request.instance_variable_get(:@current_user)
  }
)

Aris.routes({
  "api.example.com": {
    use: [rate_limit],
    "/data": { get: { to: DataHandler } }
  }
})
```

---

## Combining with Authentication

Always rate limit **after** authentication to prevent brute force:

```ruby
bearer_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) { ApiKey.valid?(token) }
)

Aris.routes({
  "api.example.com": {
    use: [bearer_auth, :rate_limit],  # Auth first, then rate limit
    "/data": { get: { to: DataHandler } }
  }
})
```

**Why this order?**
- Invalid auth fails fast (no rate limit check needed)
- Valid requests get rate limited per authenticated user

---

## Production Setup

### Use Redis Instead of Memory

The current implementation uses in-memory storage. **For production, use Redis:**

```ruby
# lib/aris/plugins/rate_limiter_redis.rb
require 'redis'

class RateLimiterRedis
  REDIS = Redis.new(url: ENV['REDIS_URL'])
  
  def initialize(limit: 100, window: 60)
    @limit = limit
    @window = window
  end
  
  def call(request, response)
    key = rate_limit_key(request)
    redis_key = "rate_limit:#{key}"
    
    count = REDIS.multi do |r|
      r.incr(redis_key)
      r.expire(redis_key, @window)
    end.first
    
    response.headers['X-RateLimit-Limit'] = @limit.to_s
    response.headers['X-RateLimit-Remaining'] = [@limit - count, 0].max.to_s
    
    if count > @limit
      response.status = 429
      response.headers['Retry-After'] = @window.to_s
      response.body = ['Rate limit exceeded. Try again later.']
      return response
    end
    
    nil
  end
  
  private
  
  def rate_limit_key(request)
    request.headers['HTTP_X_API_KEY'] || request.headers['REMOTE_ADDR']
  end
end

# Use it
redis_limiter = RateLimiterRedis.new(limit: 1000, window: 3600)

Aris.routes({
  "api.example.com": {
    use: [redis_limiter],
    "/data": { get: { to: DataHandler } }
  }
})
```

---

## Common Patterns

### Different Limits for Different Endpoints

```ruby
strict_limit = RateLimiterRedis.new(limit: 10, window: 60)
normal_limit = RateLimiterRedis.new(limit: 100, window: 60)

Aris.routes({
  "api.example.com": {
    use: [normal_limit],  # Default for all routes
    
    "/expensive": {
      use: [strict_limit],  # Override with stricter limit
      post: { to: ExpensiveHandler }
    }
  }
})
```

### Per-User Rate Limiting

```ruby
user_limiter = RateLimiterRedis.new(
  limit: 1000,
  window: 3600,
  key_extractor: ->(request) {
    # Rate limit by authenticated user ID
    user = request.instance_variable_get(:@current_user)
    "user:#{user.id}"
  }
)
```

### Bypass Rate Limiting for Premium Users

```ruby
class SmartRateLimiter
  def call(request, response)
    user = request.instance_variable_get(:@current_user)
    
    # Premium users skip rate limiting
    return nil if user&.premium?
    
    # Regular rate limiting logic
    # ...
  end
end
```

### Per-IP Brute Force Protection

```ruby
login_limiter = RateLimiterRedis.new(
  limit: 5,
  window: 300,  # 5 attempts per 5 minutes
  key_extractor: ->(request) {
    request.headers['REMOTE_ADDR']
  }
)

Aris.routes({
  "example.com": {
    "/login": {
      use: [login_limiter],  # Rate limit login attempts
      post: { to: LoginHandler }
    }
  }
})
```

---

## Testing

```ruby
class RateLimiterTest < Minitest::Test
  def test_requests_under_limit_pass
    Aris.routes({
      "api.example.com": {
        use: [:rate_limit],
        "/data": { get: { to: DataHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    Aris::Plugins::RateLimiter.reset!  # Clear state
    
    env = build_env('/data', api_key: 'test-key')
    
    # First 100 requests succeed
    100.times do
      status, _, _ = app.call(env)
      assert_equal 200, status
    end
    
    # 101st fails
    status, headers, _ = app.call(env)
    assert_equal 429, status
    assert_equal '60', headers['Retry-After']
  end
end
```

---

## Production Tips

### 1. Monitor Rate Limit Hits

```ruby
class MonitoredRateLimiter < RateLimiterRedis
  def call(request, response)
    result = super
    
    if result == response && response.status == 429
      # Log rate limit hit
      key = rate_limit_key(request)
      Rails.logger.warn("Rate limit exceeded: #{key}")
      Metrics.increment('api.rate_limit.exceeded', tags: ["key:#{key}"])
    end
    
    result
  end
end
```

### 2. Graceful Degradation

```ruby
def call(request, response)
  begin
    # Rate limiting logic
  rescue Redis::ConnectionError => e
    # If Redis is down, allow requests through
    Rails.logger.error("Rate limiter Redis error: #{e.message}")
    return nil
  end
end
```

### 3. Different Limits by Tier

```ruby
LIMITS = {
  'free' => { limit: 100, window: 3600 },
  'pro' => { limit: 1000, window: 3600 },
  'enterprise' => { limit: 10000, window: 3600 }
}

class TieredRateLimiter
  def call(request, response)
    user = request.instance_variable_get(:@current_user)
    config = LIMITS[user.tier]
    
    # Apply tier-specific limit
    # ...
  end
end
```

---

## Security Notes

**✅ Use for:**
- API endpoints
- Login/authentication endpoints
- Password reset endpoints
- Resource-intensive operations
- Public endpoints

**⚠️ Considerations:**
- Rate limit by user/token (not just IP) to prevent shared IP issues
- Use Redis for distributed systems (in-memory won't work across servers)
- Set appropriate limits (too strict = bad UX, too loose = ineffective)
- Monitor for legitimate users hitting limits

**❌ Don't rely solely on:**
- Rate limiting alone for security (defense in depth)
- IP-based limiting in cloud environments (shared IPs)

---

## Current Limitations

The built-in rate limiter:
- ✅ Works for single-server deployments
- ✅ Thread-safe with mutex
- ❌ Uses in-memory storage (won't persist across restarts)
- ❌ Won't work across multiple servers
- ❌ Fixed at 100 requests per 60 seconds

**For production:** Implement Redis-backed rate limiting as shown above.

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).