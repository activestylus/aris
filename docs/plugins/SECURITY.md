# Security Headers Plugin

Add essential security headers to protect against common web vulnerabilities.

## Installation

```ruby
require_relative 'aris/plugins/security_headers'
```

## Basic Usage

### Secure Defaults

```ruby
security = Aris::Plugins::SecurityHeaders.build

Aris.routes({
  "example.com": {
    use: [security],
    "/": { get: { to: HomeHandler } }
  }
})
```

**Headers set:**
```
X-Frame-Options: SAMEORIGIN
X-content-type-Options: nosniff
X-XSS-Protection: 0
Referrer-Policy: strict-origin-when-cross-origin
```

---

## Configuration

```ruby
security = Aris::Plugins::SecurityHeaders.build(
  x_frame_options: 'DENY',
  x_content_type_options: 'nosniff',
  hsts: { max_age: 63072000, include_subdomains: true, preload: true },
  csp: "default-src 'self'; script-src 'self' 'unsafe-inline'",
  referrer_policy: 'no-referrer',
  permissions_policy: 'geolocation=(), microphone=()'
)
```

### Options

| Option | Default | Description |
|:---|:---|:---|
| `x_frame_options` | `'SAMEORIGIN'` | Prevent clickjacking (`DENY`, `SAMEORIGIN`, `nil`) |
| `x_content_type_options` | `'nosniff'` | Prevent MIME sniffing |
| `x_xss_protection` | `'0'` | Disable legacy XSS filter (modern browsers ignore) |
| `hsts` | Not set | HTTP Strict Transport Security |
| `csp` | Not set | Content Security Policy |
| `referrer_policy` | `'strict-origin-when-cross-origin'` | Referrer behavior |
| `permissions_policy` | Not set | Control browser features |
| `defaults` | `true` | Enable default headers |

---

## Common Patterns

### Production API

```ruby
api_security = Aris::Plugins::SecurityHeaders.build(
  x_frame_options: 'DENY',
  hsts: { max_age: 31536000, include_subdomains: true },
  csp: "default-src 'none'",
  referrer_policy: 'no-referrer'
)
```

### Web Application

```ruby
web_security = Aris::Plugins::SecurityHeaders.build(
  x_frame_options: 'SAMEORIGIN',
  hsts: true,
  csp: "default-src 'self'; script-src 'self' https://cdn.example.com; style-src 'self' 'unsafe-inline'",
  referrer_policy: 'strict-origin-when-cross-origin'
)
```

### Different Security Per Route

```ruby
strict = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'DENY')
relaxed = Aris::Plugins::SecurityHeaders.build(x_frame_options: 'SAMEORIGIN')

Aris.routes({
  "example.com": {
    "/admin": {
      use: [strict],
      get: { to: AdminHandler }
    },
    "/public": {
      use: [relaxed],
      get: { to: PublicHandler }
    }
  }
})
```

---

## Header Details

**X-Frame-Options**
- `DENY` - Cannot be framed at all
- `SAMEORIGIN` - Can be framed by same origin only

**HSTS (HTTP Strict Transport Security)**
```ruby
hsts: true  # Simple: max-age=31536000; includeSubDomains

hsts: {
  max_age: 63072000,         # 2 years
  include_subdomains: true,
  preload: true              # Submit to browser preload list
}
```

**Content-Security-Policy**
```ruby
csp: "default-src 'self'; script-src 'self' 'unsafe-inline'; img-src * data:"
```

**Permissions-Policy**
```ruby
permissions_policy: 'camera=(), microphone=(), geolocation=(self)'
```

---

## Production Tips

**1. Start Strict, Relax as Needed**

```ruby
# Start with strictest settings
security = Aris::Plugins::SecurityHeaders.build(
  x_frame_options: 'DENY',
  hsts: { max_age: 31536000, include_subdomains: true },
  csp: "default-src 'self'"
)

# Relax only where necessary
```

**2. Test CSP in Report-Only Mode First**

```ruby
# Development/Staging
security = Aris::Plugins::SecurityHeaders.build(
  csp: "default-src 'self'; report-uri /csp-report"
)

# Monitor violations before enforcing
```

**3. HSTS Considerations**

- Start with short `max_age` (300 seconds) to test
- Increase gradually (3600 → 86400 → 31536000)
- Only enable `preload` when confident (irreversible!)

**4. Environment-Specific Configs**

```ruby
security = Aris::Plugins::SecurityHeaders.build(
  hsts: Rails.env.production? ? { max_age: 31536000 } : nil,
  csp: ENV['CSP_POLICY']
)
```

---

## Security Notes

- ✅ Essential first layer of defense
- ✅ Protect against clickjacking, XSS, MIME sniffing
- ✅ Combine with HTTPS (especially HSTS)
- ❌ Headers alone don't prevent all attacks
- ❌ CSP requires careful tuning for complex apps


---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).