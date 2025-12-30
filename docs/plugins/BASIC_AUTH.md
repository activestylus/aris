# Basic Authentication Plugin

HTTP Basic Authentication for protecting admin panels, staging environments, and simple protected resources.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/basic_auth'
```

## Basic Usage

### Simple Username/Password

Perfect for admin panels or staging environments:

```ruby
# config/routes.rb
admin_auth = Aris::Plugins::BasicAuth.build(
  username: ENV['ADMIN_USERNAME'],
  password: ENV['ADMIN_PASSWORD'],
  realm: 'Admin Area'
)

Aris.routes({
  "admin.example.com": {
    use: [admin_auth],
    "/dashboard": { get: { to: DashboardHandler } },
    "/users": { get: { to: AdminUsersHandler } }
  }
})
```

**Browser behavior:** Users will see a login prompt automatically.

**cURL:**
```bash
curl -u admin:secret123 https://admin.example.com/dashboard
# or
curl -H "Authorization: Basic YWRtaW46c2VjcmV0MTIz" \
  https://admin.example.com/dashboard
```

---

## Advanced Usage

### Database User Validation

Validate against your user database:

```ruby
admin_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    user = User.find_by(username: username, role: 'admin')
    
    if user && user.authenticate(password)
      # Optional: Log successful login
      LoginLog.create(user: user, timestamp: Time.now)
      true
    else
      # Optional: Log failed attempt
      Rails.logger.warn("Failed login attempt for: #{username}")
      false
    end
  },
  realm: 'Admin Panel'
)

Aris.routes({
  "admin.example.com": {
    use: [admin_auth],
    "/dashboard": { get: { to: DashboardHandler } }
  }
})
```

---

### Bcrypt Password Hashing

Secure password validation with bcrypt:

```ruby
require 'bcrypt'

# Store hashed passwords in your database
# User.create(username: 'admin', password_hash: BCrypt::Password.create('secret'))

admin_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    user = User.find_by(username: username)
    return false unless user
    
    # BCrypt comparison (constant-time)
    BCrypt::Password.new(user.password_hash) == password
  },
  realm: 'Secure Admin'
)
```

---

### LDAP/Active Directory Integration

Authenticate against LDAP:

```ruby
require 'net/ldap'

ldap_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    ldap = Net::LDAP.new(
      host: ENV['LDAP_HOST'],
      port: 389,
      auth: {
        method: :simple,
        username: "cn=#{username},dc=example,dc=com",
        password: password
      }
    )
    
    ldap.bind  # Returns true if credentials valid
  },
  realm: 'Corporate Login'
)

Aris.routes({
  "intranet.company.com": {
    use: [ldap_auth],
    "/": { get: { to: IntranetHome } }
  }
})
```

---

## Multiple Authentication Strategies

Different areas, different credentials:

```ruby
# Admin panel - super admin only
admin_auth = Aris::Plugins::BasicAuth.build(
  username: ENV['ADMIN_USER'],
  password: ENV['ADMIN_PASS'],
  realm: 'Admin Panel'
)

# Staging environment - team access
staging_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    # Multiple valid username/password pairs
    credentials = {
      'dev1' => 'devpass1',
      'dev2' => 'devpass2',
      'qa' => 'qapass'
    }
    credentials[username] == password
  },
  realm: 'Staging Environment'
)

# Partner API - partner credentials
partner_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    Partner.authenticate(username, password)
  },
  realm: 'Partner Portal'
)

Aris.routes({
  "admin.myapp.com": {
    use: [admin_auth],
    "/dashboard": { get: { to: AdminDashboard } }
  },
  "staging.myapp.com": {
    use: [staging_auth],
    "/": { get: { to: StagingHome } }
  },
  "partners.myapp.com": {
    use: [partner_auth],
    "/api": { get: { to: PartnerAPI } }
  }
})
```

---

## Accessing Credentials in Handlers

The authenticated username is attached to the request:

```ruby
class DashboardHandler
  def self.call(request, params)
    # Access the authenticated username
    username = request.instance_variable_get(:@current_user)
    
    # Load user data
    user = User.find_by(username: username)
    
    {
      message: "Welcome to your dashboard, #{user.full_name}!",
      last_login: user.last_login_at
    }
  end
end
```

---

## Combining with Other Plugins

Layer Basic Auth with other security measures:

```ruby
basic_auth = Aris::Plugins::BasicAuth.build(
  username: ENV['ADMIN_USER'],
  password: ENV['ADMIN_PASS']
)

csrf = Aris::Plugins::CsrfTokenGenerator.new
rate_limit = Aris::Plugins::RateLimiter.build(limit: 100, window: 3600)

Aris.routes({
  "admin.example.com": {
    use: [basic_auth, csrf, rate_limit],  # Execute in order
    "/dashboard": { get: { to: DashboardHandler } }
  }
})
```

**Execution order:**
1. Basic Auth validates credentials (fails fast if invalid)
2. CSRF generates token for forms
3. Rate limiter prevents brute force attacks

---

## Configuration Options

| Option | Type | Required | Description |
|:---|:---|:---|:---|
| `username` | String | * | Static username to validate against |
| `password` | String | * | Static password to validate against |
| `validator` | Proc | * | Custom validation logic `(username, password) -> Boolean` |
| `realm` | String | No | Realm for WWW-Authenticate header (default: "Restricted Area") |

**Note:** Must provide either (`username` AND `password`) OR `validator`, not both.

---

## Error Responses

**401 Unauthorized:**
```
HTTP/1.1 401 Unauthorized
content-type: text/plain
WWW-Authenticate: Basic realm="Admin Area"

Invalid username or password
```

**Browsers display a login dialog automatically** when they receive a 401 with `WWW-Authenticate: Basic`.

---

## Production Tips

### 1. Always Use HTTPS

Basic Auth sends credentials in Base64 (easily decoded). **Always use HTTPS in production.**

```ruby
# In production config
config.force_ssl = true  # Rails
# or configure your web server to enforce HTTPS
```

### 2. Use Environment Variables

```ruby
# NEVER hardcode credentials
auth = Aris::Plugins::BasicAuth.build(
  username: ENV.fetch('BASIC_AUTH_USER'),
  password: ENV.fetch('BASIC_AUTH_PASS')
)
```

### 3. Rate Limit Login Attempts

```ruby
# Prevent brute force attacks
login_rate_limit = Aris::Plugins::RateLimiter.build(
  limit: 5,
  window: 300,  # 5 attempts per 5 minutes
  key_extractor: ->(request) {
    # Rate limit by IP address
    request.headers['REMOTE_ADDR']
  }
)

Aris.routes({
  "admin.example.com": {
    use: [login_rate_limit, admin_auth],  # Rate limit BEFORE auth
    "/dashboard": { get: { to: DashboardHandler } }
  }
})
```

### 4. Log Failed Attempts

```ruby
auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    valid = validate_credentials(username, password)
    
    unless valid
      Rails.logger.warn("Failed login: #{username} from #{request.ip}")
      Metrics.increment('admin.login.failed', tags: ["username:#{username}"])
    end
    
    valid
  }
)
```

### 5. Use Strong Passwords

```ruby
# Validate password strength
auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    user = User.find_by(username: username)
    return false unless user
    
    # Check password AND ensure it meets complexity requirements
    user.authenticate(password) && user.password_meets_requirements?
  }
)
```

### 6. Different Credentials Per Environment

```ruby
# config/environments/staging.rb
STAGING_AUTH = Aris::Plugins::BasicAuth.build(
  username: ENV['STAGING_USER'],
  password: ENV['STAGING_PASS']
)

# config/environments/production.rb
ADMIN_AUTH = Aris::Plugins::BasicAuth.build(
  validator: ->(u, p) { AdminUser.authenticate(u, p) }
)
```

---

## Testing

```ruby
# test/integration/basic_auth_test.rb
require 'base64'

class BasicAuthTest < Minitest::Test
  def test_valid_credentials_grant_access
    auth = Aris::Plugins::BasicAuth.build(
      username: 'admin',
      password: 'secret123'
    )
    
    Aris.routes({
      "admin.test": {
        use: [auth],
        "/dashboard": { get: { to: DashboardHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    
    # Encode credentials
    credentials = Base64.strict_encode64("admin:secret123")
    
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/dashboard',
      'HTTP_HOST' => 'admin.test',
      'HTTP_AUTHORIZATION' => "Basic #{credentials}",
      'rack.input' => StringIO.new('')
    }
    
    status, _, body = app.call(env)
    assert_equal 200, status
  end
  
  def test_invalid_credentials_denied
    auth = Aris::Plugins::BasicAuth.build(
      username: 'admin',
      password: 'secret123'
    )
    
    Aris.routes({
      "admin.test": {
        use: [auth],
        "/dashboard": { get: { to: DashboardHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    credentials = Base64.strict_encode64("admin:wrongpass")
    
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/dashboard',
      'HTTP_HOST' => 'admin.test',
      'HTTP_AUTHORIZATION' => "Basic #{credentials}",
      'rack.input' => StringIO.new('')
    }
    
    status, _, _ = app.call(env)
    assert_equal 401, status
  end
end
```

---

## Common Patterns

### Protect Entire Staging Environment

```ruby
# Only protect in staging
if ENV['RACK_ENV'] == 'staging'
  staging_auth = Aris::Plugins::BasicAuth.build(
    username: ENV['STAGING_USER'],
    password: ENV['STAGING_PASS'],
    realm: 'Staging Environment'
  )
  
  Aris.routes({
    "staging.myapp.com": {
      use: [staging_auth],  # Everything behind auth
      "/": { get: { to: HomeHandler } },
      "/api": { get: { to: ApiHandler } }
    }
  })
end
```

### Public Health Check

```ruby
Aris.routes({
  "admin.example.com": {
    use: [admin_auth],
    
    "/dashboard": { get: { to: DashboardHandler } },
    
    "/health": {
      use: nil,  # Clear auth for health checks
      get: { to: HealthHandler }
    }
  }
})
```

### Layered Authentication

```ruby
# Basic Auth for staging, then Bearer for API
staging_auth = Aris::Plugins::BasicAuth.build(
  username: ENV['STAGING_USER'],
  password: ENV['STAGING_PASS']
)

api_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) { ApiKey.valid?(token) }
)

Aris.routes({
  "staging-api.example.com": {
    use: [staging_auth, api_auth],  # Both required!
    "/data": { get: { to: DataHandler } }
  }
})
```

### Admin Panel with Role Check

```ruby
admin_auth = Aris::Plugins::BasicAuth.build(
  validator: ->(username, password) {
    user = User.find_by(username: username)
    
    # Check password AND role
    user && 
      user.authenticate(password) && 
      user.role == 'admin'
  }
)
```

---

## Limitations

### Colons in Usernames

Basic Auth uses `:` as the delimiter between username and password. **Usernames containing colons are not supported** and will be truncated at the first colon character.

```ruby
# ❌ Won't work correctly
username: "user:name"  # Splits into username="user", password="name"

# ✅ Use these alternatives instead
username: "user_name"
username: "username"
```

If you need special characters in usernames, consider using **Bearer Token Auth** instead.

### Browser Logout

Browsers cache Basic Auth credentials and don't provide a standard "logout" mechanism. Users must:
- Close all browser windows/tabs
- Clear browser cache
- Use browser's "forget this password" feature

For better UX with logout functionality, consider **cookie-based session auth** or **Bearer tokens**.

### Credential Exposure

Credentials are sent with **every request** in the Authorization header. While Base64 encoded, they're easily decoded. **Always use HTTPS** in production.

---

## Security Checklist

- ✅ Use HTTPS everywhere (Basic Auth is insecure over HTTP)
- ✅ Use environment variables for credentials
- ✅ Use bcrypt or similar for password hashing
- ✅ Rate limit authentication attempts
- ✅ Log failed login attempts
- ✅ Use strong passwords (12+ characters, mixed case, numbers, symbols)
- ✅ Rotate passwords regularly
- ✅ Different credentials per environment
- ❌ Never commit credentials to version control
- ❌ Never log full credentials (only log username)
- ❌ Never use Basic Auth as your primary user authentication system

---

## When to Use Basic Auth

**✅ Good for:**
- Admin panels with limited users
- Staging/preview environments
- Internal tools and dashboards
- CI/CD webhook endpoints
- Quick prototyping
- Adding a second layer of security

**❌ Not ideal for:**
- Primary user authentication
- Public-facing applications
- Mobile apps (credentials stored on device)
- APIs with many users
- Applications requiring granular permissions

**Better alternatives:**
- **Bearer Token Auth** - For APIs and mobile apps
- **JWT** - For stateless authentication
- **OAuth2** - For third-party integrations
- **Session Cookies** - For traditional web apps

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).