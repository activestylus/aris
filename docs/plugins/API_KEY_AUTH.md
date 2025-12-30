
# API Key Auth Plugin

Simple API key authentication via custom header.

## Installation

```ruby
require_relative 'aris/plugins/api_key_auth'
```

## Basic Usage

### Single Key

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(key: ENV['API_KEY'])

Aris.routes({
  "api.example.com": {
    use: [auth],
    "/data": { get: { to: DataHandler } }
  }
})
```

**Request:**
```bash
curl -H "X-API-Key: your-secret-key" https://api.example.com/data
```

---

## Configuration

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  key: 'secret-key',              # Single key
  keys: ['key1', 'key2'],         # Multiple keys
  validator: ->(k) { valid?(k) }, # Custom validation
  header: 'X-API-Key',            # Header name (default)
  realm: 'API'                     # Realm for WWW-Authenticate
)
```

### Options

| Option | Required | Description |
|:---|:---|:---|
| `key` | * | Single valid key |
| `keys` | * | Array of valid keys |
| `validator` | * | Custom validation `(key) -> Boolean` |
| `header` | No | Header name (default: `X-API-Key`) |
| `realm` | No | Realm (default: `API`) |

**Note:** Must provide `key`, `keys`, OR `validator`.

---

## Common Patterns

### Multiple Valid Keys

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  keys: [
    ENV['PUBLIC_API_KEY'],
    ENV['PARTNER_API_KEY'],
    ENV['INTERNAL_API_KEY']
  ]
)
```

### Database Validation

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  validator: ->(key) {
    ApiKey.exists?(key: key, active: true)
  }
)
```

### Redis-Cached Validation

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  validator: ->(key) {
    Rails.cache.fetch("api_key:#{key}", expires_in: 5.minutes) do
      ApiKey.valid?(key)
    end
  }
)
```

### Custom Header

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  key: ENV['API_KEY'],
  header: 'X-Custom-API-Key'
)
```

**Request:**
```bash
curl -H "X-Custom-API-Key: secret" https://api.example.com/data
```

### Per-Domain Keys

```ruby
public_auth = Aris::Plugins::ApiKeyAuth.build(key: ENV['PUBLIC_KEY'])
admin_auth = Aris::Plugins::ApiKeyAuth.build(key: ENV['ADMIN_KEY'])

Aris.routes({
  "api.example.com": {
    use: [public_auth],
    "/data": { get: { to: DataHandler } }
  },
  "admin-api.example.com": {
    use: [admin_auth],
    "/admin": { get: { to: AdminHandler } }
  }
})
```

---

## Accessing Key in Handler

```ruby
class DataHandler
  def self.call(request, params)
    api_key = request.instance_variable_get(:@api_key)
    
    # Look up associated user/account
    account = Account.find_by(api_key: api_key)
    
    { data: account.data }
  end
end
```

---

## Production Tips

**1. Use Environment Variables**

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  key: ENV.fetch('API_SECRET_KEY')
)
```

**2. Rotate Keys Regularly**

```ruby
# Support old + new during rotation
auth = Aris::Plugins::ApiKeyAuth.build(
  keys: [ENV['API_KEY_CURRENT'], ENV['API_KEY_PREVIOUS']]
)
```

**3. Rate Limit by Key**

```ruby
rate_limit = RateLimiter.build(
  key_extractor: ->(request) {
    request.instance_variable_get(:@api_key)
  }
)

Aris.routes({
  "api.example.com": {
    use: [api_key_auth, rate_limit],  # Auth first, then rate limit by key
    "/data": { get: { to: DataHandler } }
  }
})
```

**4. Log Failed Attempts**

```ruby
auth = Aris::Plugins::ApiKeyAuth.build(
  validator: ->(key) {
    valid = ApiKey.valid?(key)
    unless valid
      Rails.logger.warn("Invalid API key attempt: #{key[0..8]}...")
    end
    valid
  }
)
```

---

## Error Response

**401 Unauthorized:**
```json
{
  "error": "Unauthorized",
  "message": "Invalid API key"
}
```

**Headers:**
```
HTTP/1.1 401 Unauthorized
content-type: application/json
WWW-Authenticate: ApiKey realm="API"
```

---

## Security Notes

- ✅ Use HTTPS always (keys sent in plain text)
- ✅ Store keys hashed in database
- ✅ Rotate keys regularly
- ✅ Different keys per client/environment
- ✅ Combine with rate limiting
- ❌ Never log full keys
- ❌ Never commit keys to version control

---

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).