# Bearer Token Authentication Plugin

Dead-simple Bearer token authentication for API endpoints.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/bearer_auth'
```

## Basic Usage

### Simple Token Validation

Perfect for internal APIs or development:

```ruby
# config/routes.rb
api_auth = Aris::Plugins::BearerAuth.build(
  token: ENV['API_SECRET_TOKEN']
)

Aris.routes({
  "api.example.com": {
    use: [api_auth],
    "/users": { get: { to: UsersHandler } },
    "/posts": { get: { to: PostsHandler } }
  }
})
```

**Request:**
```bash
curl -H "Authorization: Bearer your-secret-token" \
  https://api.example.com/users
```

---

## Advanced Usage

### Database Token Validation

Validate against your user/token database:

```ruby
api_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) {
    # Check if token exists and is valid
    api_key = ApiKey.find_by(token: token, active: true)
    
    if api_key && !api_key.expired?
      # Optional: Track usage
      api_key.update(last_used_at: Time.now)
      true
    else
      false
    end
  },
  realm: 'MyApp API v1'
)

Aris.routes({
  "api.example.com": {
    use: [api_auth],
    "/data": { get: { to: DataHandler } }
  }
})
```

---

### Redis Token Store

For high-performance token validation:

```ruby
require 'redis'
REDIS = Redis.new

api_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) {
    # Check Redis cache first (fast!)
    cached = REDIS.get("token:#{token}")
    return cached == "valid" if cached
    
    # Fallback to database
    user = User.find_by(api_token: token)
    if user
      REDIS.setex("token:#{token}", 3600, "valid")  # Cache for 1 hour
      true
    else
      REDIS.setex("token:#{token}", 300, "invalid")  # Cache misses too
      false
    end
  }
)
```

---

### JWT Token Validation

Integrate with JWT for stateless authentication:

```ruby
require 'jwt'

jwt_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) {
    begin
      payload = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256')
      
      # Check expiration
      exp = payload[0]['exp']
      exp && exp > Time.now.to_i
    rescue JWT::DecodeError, JWT::ExpiredSignature
      false
    end
  },
  realm: 'JWT API'
)

Aris.routes({
  "api.example.com": {
    use: [jwt_auth],
    "/protected": { get: { to: ProtectedHandler } }
  }
})
```

---

## Multiple Authentication Strategies

Different endpoints, different tokens:

```ruby
# Admin API - super secret token
admin_auth = Aris::Plugins::BearerAuth.build(
  token: ENV['ADMIN_SECRET'],
  realm: 'Admin Panel'
)

# Public API - database validation
public_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) { ApiKey.valid?(token) },
  realm: 'Public API'
)

# Partner API - partner-specific tokens
partner_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) { 
    Partner.find_by(api_key: token, status: 'active') 
  },
  realm: 'Partner Integration'
)

Aris.routes({
  "admin.myapp.com": {
    use: [admin_auth],
    "/dashboard": { get: { to: AdminDashboard } }
  },
  "api.myapp.com": {
    use: [public_auth],
    "/users": { get: { to: UsersAPI } }
  },
  "partner.myapp.com": {
    use: [partner_auth],
    "/webhooks": { post: { to: WebhookHandler } }
  }
})
```

---

## Accessing the Token in Handlers

The validated token is attached to the request:

```ruby
class UsersHandler
  def self.call(request, params)
    # Access the bearer token
    token = request.instance_variable_get(:@bearer_token)
    
    # Use it to identify the user
    api_key = ApiKey.find_by(token: token)
    user = api_key.user
    
    {
      message: "Hello, #{user.name}!",
      token_expires: api_key.expires_at
    }
  end
end
```

---

## Combining with Other Plugins

Layer authentication with rate limiting and CORS:

```ruby
cors = Aris::Plugins::Cors.build(origins: ['https://app.example.com'])
auth = Aris::Plugins::BearerAuth.build(validator: ->(t) { ApiKey.valid?(t) })
rate_limit = Aris::Plugins::RateLimiter.build(limit: 1000, window: 3600)

Aris.routes({
  "api.example.com": {
    use: [cors, auth, rate_limit],  # Execute in order
    "/data": { get: { to: DataHandler } }
  }
})
```

**Execution order matters:**
1. CORS headers set first (for preflight)
2. Auth validates token (fails fast if invalid)
3. Rate limiter only runs for authenticated users (saves Redis calls)

---

## Configuration Options

| Option | Type | Required | Description |
|:---|:---|:---|:---|
| `token` | String | * | Static token to validate against |
| `validator` | Proc | * | Custom validation logic `(token) -> Boolean` |
| `realm` | String | No | Realm for WWW-Authenticate header (default: "API") |

**Note:** Must provide either `token` OR `validator`, not both.

---

## Error Responses

All errors return JSON with consistent format:

**401 Unauthorized:**
```json
{
  "error": "Unauthorized",
  "message": "Invalid or expired token"
}
```

**Headers:**
```
HTTP/1.1 401 Unauthorized
content-type: application/json
WWW-Authenticate: Bearer realm="API"
```

---

## Production Tips

### 1. Use Environment Variables
```ruby
# NEVER hardcode tokens in source code
auth = Aris::Plugins::BearerAuth.build(
  token: ENV.fetch('API_SECRET_TOKEN')  # Fails fast if missing
)
```

### 2. Cache Token Lookups
```ruby
# Cache in Redis/Memcached to avoid DB hits
auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) {
    Rails.cache.fetch("token:#{token}", expires_in: 5.minutes) do
      ApiKey.exists?(token: token, active: true)
    end
  }
)
```

### 3. Log Failed Attempts
```ruby
auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) {
    valid = ApiKey.valid?(token)
    unless valid
      Rails.logger.warn("Failed auth attempt with token: #{token[0..8]}...")
      Metrics.increment('api.auth.failed')
    end
    valid
  }
)
```

### 4. Rate Limit by Token
```ruby
# Combine with rate limiter for per-token limits
token_rate_limit = Aris::Plugins::RateLimiter.build(
  key_extractor: ->(request) {
    request.instance_variable_get(:@bearer_token)
  }
)

Aris.routes({
  "api.example.com": {
    use: [auth, token_rate_limit],  # Auth first, then rate limit by token
    "/data": { get: { to: DataHandler } }
  }
})
```

---

## Testing

```ruby
# test/integration/api_auth_test.rb
class ApiAuthTest < Minitest::Test
  def test_valid_token_grants_access
    auth = Aris::Plugins::BearerAuth.build(token: 'test-token-123')
    
    Aris.routes({
      "api.test": {
        use: [auth],
        "/data": { get: { to: DataHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/data',
      'HTTP_HOST' => 'api.test',
      'HTTP_AUTHORIZATION' => 'Bearer test-token-123',
      'rack.input' => StringIO.new('')
    }
    
    status, _, body = app.call(env)
    assert_equal 200, status
  end
end
```

---

## Common Patterns

### Health Check Bypass
```ruby
Aris.routes({
  "api.example.com": {
    use: [auth],
    
    "/users": { get: { to: UsersHandler } },
    
    "/health": {
      use: nil,  # Clear auth for health checks
      get: { to: HealthHandler }
    }
  }
})
```

### Scope-Specific Auth
```ruby
Aris.routes({
  "example.com": {
    "/public": {
      # No auth
      "/blog": { get: { to: BlogHandler } }
    },
    "/api": {
      use: [api_auth],  # Auth only for /api/* routes
      "/users": { get: { to: UsersHandler } }
    }
  }
})
```

---

## Security Notes

- ✅ Always use HTTPS in production (tokens sent in headers)
- ✅ Rotate tokens regularly
- ✅ Use different tokens for different environments
- ✅ Log failed authentication attempts
- ✅ Set short expiration times for JWT tokens
- ❌ Never log full tokens (log only first 8 chars)
- ❌ Never commit tokens to version control

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).