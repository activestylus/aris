# CORS Plugin

Enable Cross-Origin Resource Sharing (CORS) for APIs accessed from web browsers on different domains.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/cors'
```

## Basic Usage

### Allow All Origins

```ruby
cors = Aris::Plugins::Cors.build(origins: '*')

Aris.routes({
  "api.example.com": {
    use: [cors],
    "/data": { get: { to: DataHandler } }
  }
})
```

**Headers set:**
```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: content-type, Authorization
Access-Control-Max-Age: 86400
```

### Specific Origins

```ruby
cors = Aris::Plugins::Cors.build(
  origins: [
    'https://app.example.com',
    'https://admin.example.com'
  ]
)
```

Only requests from these origins get CORS headers. Others are blocked by the browser.

---

## Configuration

```ruby
cors = Aris::Plugins::Cors.build(
  origins: ['https://app.example.com'],  # Array or '*'
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  headers: ['content-type', 'Authorization', 'X-Custom'],
  credentials: true,
  max_age: 3600,  # Cache preflight for 1 hour
  expose_headers: ['X-Total-Count', 'X-Page']
)
```

| Option | Default | Description |
|:---|:---|:---|
| `origins` | `'*'` | Allowed origins (array or wildcard) |
| `methods` | All common methods | HTTP methods to allow |
| `headers` | content-type, Authorization | Headers clients can send |
| `credentials` | `false` | Allow cookies/auth headers |
| `max_age` | `86400` | Preflight cache time (seconds) |
| `expose_headers` | `[]` | Headers clients can read |

---

## Common Patterns

### Frontend + API on Different Domains

```ruby
# API on api.example.com
# Frontend on app.example.com

cors = Aris::Plugins::Cors.build(
  origins: ['https://app.example.com'],
  credentials: true  # Allow cookies
)

Aris.routes({
  "api.example.com": {
    use: [cors],
    "/users": { get: { to: UsersHandler } }
  }
})
```

**Frontend (React/Vue):**
```javascript
fetch('https://api.example.com/users', {
  credentials: 'include'  // Send cookies
})
```

### Multiple Environments

```ruby
origins = case ENV['RACK_ENV']
when 'production'
  ['https://app.example.com']
when 'staging'
  ['https://staging.example.com']
when 'development'
  ['http://localhost:3000', 'http://localhost:8080']
end

cors = Aris::Plugins::Cors.build(origins: origins)
```

### Public API + Private Admin API

```ruby
public_cors = Aris::Plugins::Cors.build(origins: '*')

admin_cors = Aris::Plugins::Cors.build(
  origins: ['https://admin.example.com'],
  credentials: true
)

Aris.routes({
  "api.example.com": {
    use: [public_cors],
    "/public": { get: { to: PublicHandler } }
  },
  "admin-api.example.com": {
    use: [admin_cors],
    "/admin": { get: { to: AdminHandler } }
  }
})
```

---

## How CORS Works

**Simple Request (GET, POST with simple headers):**
1. Browser sends request with `Origin` header
2. Server responds with `Access-Control-Allow-Origin`
3. Browser allows response if origin matches

**Preflight Request (PUT, DELETE, custom headers):**
1. Browser sends OPTIONS request first
2. Server responds with allowed methods/headers
3. Browser sends actual request if allowed
4. CORS plugin automatically handles OPTIONS with 204 response

---

## Troubleshooting

**"CORS error" in browser console:**

Check origin is in allowed list:
```ruby
cors = Aris::Plugins::Cors.build(
  origins: ['https://app.example.com']  # Must match exactly
)
```

**Credentials not working:**

Enable both in plugin and frontend:
```ruby
cors = Aris::Plugins::Cors.build(
  origins: ['https://app.example.com'],  # Can't use '*' with credentials
  credentials: true
)
```

```javascript
fetch(url, { credentials: 'include' })
```

**Custom headers blocked:**

Add to allowed headers:
```ruby
cors = Aris::Plugins::Cors.build(
  headers: ['content-type', 'Authorization', 'X-My-Custom-Header']
)
```

---

## Production Tips

**1. Be Specific in Production**

```ruby
# ❌ Too permissive
cors = Aris::Plugins::Cors.build(origins: '*')

# ✅ Explicit origins
cors = Aris::Plugins::Cors.build(
  origins: [
    'https://app.example.com',
    'https://www.example.com'
  ]
)
```

**2. Use Environment Variables**

```ruby
cors = Aris::Plugins::Cors.build(
  origins: ENV['CORS_ORIGINS'].split(',')
)
```

**3. Different CORS for Different Routes**

```ruby
Aris.routes({
  "api.example.com": {
    "/public": {
      use: [public_cors],
      "/posts": { get: { to: PostsHandler } }
    },
    "/admin": {
      use: [admin_cors],
      "/users": { delete: { to: DeleteUserHandler } }
    }
  }
})
```

---

## Important: OPTIONS Routes

CORS preflight requires OPTIONS to be defined:

```ruby
Aris.routes({
  "api.example.com": {
    use: [cors],
    "/users": {
      get: { to: UsersHandler },
      post: { to: CreateUserHandler },
      options: { to: UsersHandler }  # Required for preflight
    }
  }
})
Or use a catch-all handler:
rubyclass OptionsHandler
  def self.call(request, params)
    # CORS plugin handles the response
    nil
  end
end
```

This is a common pattern in web frameworks - the route must exist for middleware to run.

----

## Security Notes

- ✅ CORS prevents malicious sites from making requests on behalf of users
- ✅ Always use specific origins in production (not `'*'`)
- ✅ Only enable `credentials: true` when necessary
- ✅ Combine with CSRF protection for state-changing requests
- ❌ CORS alone doesn't prevent XSS or authentication bypass
- ❌ CORS is browser-enforced (curl/Postman ignore it)

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).
```

**Add to `lib/aris.rb`:**
```ruby
require_relative 'aris/plugins/cors'
```

All tests passing! 🎉