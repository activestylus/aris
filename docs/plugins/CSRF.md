# CSRF Protection Plugin

Cross-Site Request Forgery (CSRF) protection using token validation. Protects form submissions and state-changing requests from malicious sites.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/csrf'
```

## How It Works

CSRF protection is a **two-phase system**:

1. **Token Generation** (`CsrfTokenGenerator`) - Runs on GET/HEAD requests, generates a unique token and stores it in thread-local storage
2. **Token Validation** (`CsrfProtection`) - Runs on POST/PUT/PATCH/DELETE requests, validates the submitted token against the stored token

Both plugins are registered together under the `:csrf` symbol and execute in order.

---

## Basic Usage

### Simple Form Protection

```ruby
# config/routes.rb
Aris.routes({
  "example.com": {
    use: [:csrf],  # Both generator and protection
    
    "/form": {
      get: { to: FormHandler },      # Generates token
      post: { to: FormSubmitHandler } # Validates token
    }
  }
})
```

**In your form (GET request generates token):**

```ruby
class FormHandler
  def self.call(request, params)
    # Get the generated token
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    <<~HTML
      <form action="/form" method="POST">
        <input type="hidden" name="csrf_token" value="#{token}">
        <input type="text" name="username">
        <button type="submit">Submit</button>
      </form>
    HTML
  end
end
```

**In your form handler (POST validates token):**

```ruby
class FormSubmitHandler
  def self.call(request, params)
    # Token already validated by CsrfProtection plugin
    # If we get here, the token was valid!
    
    username = params['username']
    "Form submitted successfully for #{username}!"
  end
end
```

**Send the token in the header:**

```html
<form action="/form" method="POST">
  <input type="hidden" name="csrf_token" id="csrf-token">
  <input type="text" name="username">
  <button type="submit">Submit</button>
</form>

<script>
  // Set token from meta tag or data attribute
  document.getElementById('csrf-token').value = '<%= token %>';
</script>
```

---

## AJAX/Fetch Requests

### Using Headers (Recommended)

```javascript
// Get token from the page (set during GET request)
const csrfToken = document.querySelector('meta[name="csrf-token"]').content;

// Send with every state-changing request
fetch('/api/users', {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    'X-CSRF-Token': csrfToken  // Plugin checks this header
  },
  body: JSON.stringify({ name: 'Alice' })
});
```

**In your HTML template:**

```html
<!DOCTYPE html>
<html>
<head>
  <meta name="csrf-token" content="<%= csrf_token %>">
</head>
<body>
  <!-- Your app -->
</body>
</html>
```

**Helper to get the token:**

```ruby
class LayoutHelper
  def self.csrf_token
    Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
  end
end
```

---

### Using Request Body

```javascript
const csrfToken = document.querySelector('meta[name="csrf-token"]').content;

fetch('/api/users', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    csrf_token: csrfToken,  // Include in body
    name: 'Alice'
  })
});
```

---

## Single Page Applications (SPA)

### Initial Token on Page Load

```ruby
class AppHandler
  def self.call(request, params)
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="csrf-token" content="#{token}">
      </head>
      <body>
        <div id="app"></div>
        <script>
          // Make token available to your SPA
          window.CSRF_TOKEN = '#{token}';
        </script>
        <script src="/app.js"></script>
      </body>
      </html>
    HTML
  end
end
```

### React Example

```jsx
// App.js
import React, { useState, useEffect } from 'react';

function App() {
  const [csrfToken] = useState(window.CSRF_TOKEN);
  
  const handleSubmit = async (data) => {
    const response = await fetch('/api/data', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify(data)
    });
    
    return response.json();
  };
  
  return <YourComponent onSubmit={handleSubmit} />;
}
```

### Vue Example

```javascript
// main.js
import { createApp } from 'vue';
import axios from 'axios';

// Set CSRF token globally for all axios requests
axios.defaults.headers.common['X-CSRF-Token'] = window.CSRF_TOKEN;

const app = createApp(App);
app.config.globalProperties.$http = axios;
app.mount('#app');
```

```vue
<!-- Component.vue -->
<script>
export default {
  methods: {
    async submitForm(data) {
      // Token automatically included via axios defaults
      const response = await this.$http.post('/api/data', data);
      return response.data;
    }
  }
}
</script>
```

---

## API-Only Routes (Skip CSRF)

APIs using Bearer tokens don't need CSRF protection:

```ruby
bearer_auth = Aris::Plugins::BearerAuth.build(
  validator: ->(token) { ApiKey.valid?(token) }
)

Aris.routes({
  "example.com": {
    "/web": {
      use: [:csrf],  # Web routes need CSRF
      "/form": {
        get: { to: FormHandler },
        post: { to: FormSubmitHandler }
      }
    },
    
    "/api": {
      use: [bearer_auth],  # API uses Bearer tokens, no CSRF needed
      "/data": {
        post: { to: ApiDataHandler }
      }
    }
  }
})
```

---

## Route-Level Control

### Public Forms (No CSRF)

```ruby
Aris.routes({
  "example.com": {
    use: [:csrf],  # Domain-level CSRF
    
    "/admin": {
      # Protected forms
      get: { to: AdminFormHandler },
      post: { to: AdminSubmitHandler }
    },
    
    "/contact": {
      use: nil,  # Clear CSRF for public contact form
      get: { to: ContactFormHandler },
      post: { to: ContactSubmitHandler }
    }
  }
})
```

**Warning:** Only disable CSRF for truly public, read-only, or idempotent operations.

---

## Combining with Authentication

Always put CSRF **after** authentication:

```ruby
basic_auth = Aris::Plugins::BasicAuth.build(
  username: ENV['ADMIN_USER'],
  password: ENV['ADMIN_PASS']
)

Aris.routes({
  "admin.example.com": {
    use: [basic_auth, :csrf],  # Auth first, then CSRF
    
    "/dashboard": { get: { to: DashboardHandler } },
    "/users": {
      post: { to: CreateUserHandler },
      delete: { to: DeleteUserHandler }
    }
  }
})
```

**Why this order?**
1. Unauthenticated requests fail at auth (fast)
2. Authenticated requests proceed to CSRF validation
3. Valid CSRF tokens reach the handler

---

## Token Storage

The CSRF token is stored in **thread-local storage** at:

```ruby
Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
```

This is automatically:
- ✅ Set by `CsrfTokenGenerator` on GET/HEAD requests
- ✅ Validated by `CsrfProtection` on POST/PUT/PATCH/DELETE requests
- ✅ Cleaned up after the request completes

**Thread-safe:** Each request thread has its own isolated token.

---

## Error Responses

**403 Forbidden (Invalid Token):**

```
HTTP/1.1 403 Forbidden
content-type: text/plain

CSRF Token Invalid
```

**Common causes:**
- Token not included in request
- Token mismatch (form was loaded in one session, submitted in another)
- Token expired (if you implement expiration)
- Double-submit of same form

---

## Testing

```ruby
# test/integration/csrf_test.rb
class CsrfIntegrationTest < Minitest::Test
  def test_get_request_generates_token
    Aris.routes({
      "example.com": {
        use: [:csrf],
        "/form": { get: { to: FormHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/form',
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new('')
    }
    
    app.call(env)
    
    # Token should be set
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    assert token
    assert token.length > 20
  end
  
  def test_post_without_token_fails
    Aris.routes({
      "example.com": {
        use: [:csrf],
        "/form": { post: { to: FormSubmitHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/form',
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new('')
    }
    
    status, _, body = app.call(env)
    
    assert_equal 403, status
    assert_match /CSRF Token Invalid/, body.first
  end
  
  def test_post_with_valid_token_succeeds
    Aris.routes({
      "example.com": {
        use: [:csrf],
        "/form": {
          get: { to: FormHandler },
          post: { to: FormSubmitHandler }
        }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    
    # First, GET to generate token
    get_env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/form',
      'HTTP_HOST' => 'example.com',
      'rack.input' => StringIO.new('')
    }
    app.call(get_env)
    
    # Get the generated token
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    # Now POST with the token
    post_env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/form',
      'HTTP_HOST' => 'example.com',
      'HTTP_X_CSRF_TOKEN' => token,
      'rack.input' => StringIO.new('')
    }
    
    status, _, body = app.call(post_env)
    
    assert_equal 200, status
  end
end
```

---

## Production Tips

### 1. Use Meta Tags for Token Distribution

```html
<!DOCTYPE html>
<html>
<head>
  <meta name="csrf-token" content="<%= csrf_token %>">
</head>
<body>
  <!-- Your app -->
</body>
</html>
```

```javascript
// Global setup - runs once
const token = document.querySelector('meta[name="csrf-token"]').content;

// Use in all AJAX libraries
$.ajaxSetup({
  headers: { 'X-CSRF-Token': token }
});

// Or with axios
axios.defaults.headers.common['X-CSRF-Token'] = token;

// Or with fetch wrapper
window.fetchWithCSRF = (url, options = {}) => {
  options.headers = options.headers || {};
  options.headers['X-CSRF-Token'] = token;
  return fetch(url, options);
};
```

### 2. Token Rotation Strategy

For high-security applications, rotate tokens periodically:

```ruby
class EnhancedCsrfTokenGenerator
  def self.call(request, response)
    if request.method == 'GET' || request.method == 'HEAD'
      # Generate new token with timestamp
      token = "#{SecureRandom.urlsafe_base64(32)}:#{Time.now.to_i}"
      Thread.current[Aris::Plugins::CSRF_THREAD_KEY] = token
    end
    nil
  end
end

class EnhancedCsrfProtection
  TOKEN_EXPIRY = 3600  # 1 hour
  
  def self.call(request, response)
    return nil unless ['POST', 'PUT', 'PATCH', 'DELETE'].include?(request.method)
    
    expected = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    provided = request.headers['HTTP_X_CSRF_TOKEN']
    
    # Check token exists
    return halt_forbidden(response) unless expected && provided
    
    # Parse timestamp
    token, timestamp = provided.split(':')
    return halt_forbidden(response) unless timestamp
    
    # Check expiry
    if Time.now.to_i - timestamp.to_i > TOKEN_EXPIRY
      return halt_forbidden(response, 'CSRF token expired')
    end
    
    # Validate token
    return halt_forbidden(response) unless provided == expected
    
    nil
  end
  
  def self.halt_forbidden(response, message = 'CSRF Token Invalid')
    response.status = 403
    response.body = [message]
    response
  end
end
```

### 3. Double-Submit Cookie Pattern (Alternative)

For stateless CSRF protection:

```ruby
class CookieBasedCsrf
  def self.call(request, response)
    if request.method == 'GET' || request.method == 'HEAD'
      # Generate token
      token = SecureRandom.urlsafe_base64(32)
      
      # Set as cookie
      response.headers['Set-Cookie'] = "csrf_token=#{token}; HttpOnly; Secure; SameSite=Strict"
      
      # Also store for comparison
      Thread.current[:csrf_cookie] = token
    elsif ['POST', 'PUT', 'PATCH', 'DELETE'].include?(request.method)
      # Get token from cookie
      cookie_token = parse_cookie(request.headers['HTTP_COOKIE'])
      
      # Get token from header
      header_token = request.headers['HTTP_X_CSRF_TOKEN']
      
      # Both must exist and match
      unless cookie_token && header_token && cookie_token == header_token
        response.status = 403
        response.body = ['CSRF Token Invalid']
        return response
      end
    end
    
    nil
  end
  
  def self.parse_cookie(cookie_string)
    return nil unless cookie_string
    cookies = cookie_string.split(';').map { |c| c.strip.split('=', 2) }.to_h
    cookies['csrf_token']
  end
end
```

### 4. Idempotent Endpoints (Skip CSRF)

Some POST endpoints are idempotent and safe from CSRF:

```ruby
Aris.routes({
  "example.com": {
    use: [:csrf],
    
    "/search": {
      use: nil,  # Search is idempotent, no CSRF needed
      post: { to: SearchHandler }
    },
    
    "/user": {
      # Mutations need CSRF
      post: { to: CreateUserHandler },
      delete: { to: DeleteUserHandler }
    }
  }
})
```

---

## Common Patterns

### Multi-Step Forms

```ruby
class StepOneHandler
  def self.call(request, params)
    token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
    
    # Store token in session/database for next step
    SessionStore.set(params[:session_id], csrf_token: token)
    
    # Render form with hidden token
    render_form(token)
  end
end

class StepTwoHandler
  def self.call(request, params)
    # Token validated by plugin
    # Continue to next step
  end
end
```

### File Uploads

```html
<form action="/upload" method="POST" enctype="multipart/form-data">
  <input type="hidden" name="csrf_token" value="<%= token %>">
  <input type="file" name="file">
  <button type="submit">Upload</button>
</form>
```

### GraphQL

```javascript
const client = new ApolloClient({
  uri: '/graphql',
  headers: {
    'X-CSRF-Token': window.CSRF_TOKEN
  }
});
```

---

## Security Notes

### What CSRF Protects Against

✅ Malicious sites submitting forms to your application
✅ Malicious AJAX requests from other origins
✅ Clickjacking combined with form submissions
✅ Cross-site request attacks

### What CSRF Does NOT Protect Against

❌ XSS (Cross-Site Scripting) - Use Content Security Policy
❌ SQL Injection - Use parameterized queries
❌ Authentication bypass - Use proper auth plugins
❌ Same-origin attacks - User's own browser extensions can still attack

### Best Practices

- ✅ Use CSRF for all state-changing operations (POST/PUT/PATCH/DELETE)
- ✅ Combine with SameSite cookies for defense-in-depth
- ✅ Use HTTPS to prevent token interception
- ✅ Regenerate tokens after authentication
- ✅ Set short expiration times for high-security applications
- ✅ Use Content Security Policy headers
- ❌ Never skip CSRF for authenticated routes
- ❌ Never expose tokens in URLs (use headers or body)
- ❌ Never log CSRF tokens

---

## When to Use CSRF Protection

**✅ Always use for:**
- Form submissions
- State-changing API endpoints
- Admin panels
- User account modifications
- Financial transactions
- Any POST/PUT/PATCH/DELETE requests

**❌ Not needed for:**
- Public read-only APIs
- Bearer token authenticated APIs (different attack vector)
- GET requests (should be idempotent anyway)
- Webhook endpoints (use signature verification instead)

---

## Troubleshooting

### "CSRF Token Invalid" on valid requests

**Cause:** Token not being sent with request

**Fix:** Check that token is included in `X-CSRF-Token` header

```javascript
// Verify token is being sent
console.log('Token:', document.querySelector('meta[name="csrf-token"]').content);

fetch('/api/data', {
  method: 'POST',
  headers: {
    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
  },
  body: JSON.stringify(data)
});
```

### Token works in browser but not in tests

**Cause:** Thread-local storage not persisting between requests in tests

**Fix:** Set token in the same thread as the request

```ruby
def test_with_csrf
  app = Aris::Adapters::RackApp.new
  
  # GET to generate token (happens in this thread)
  app.call(get_env)
  token = Thread.current[Aris::Plugins::CSRF_THREAD_KEY]
  
  # POST with token (same thread, token still available)
  post_env['HTTP_X_CSRF_TOKEN'] = token
  app.call(post_env)
end
```

### SPA token expires

**Cause:** Long-lived single-page app, token generated on initial page load

**Fix:** Refresh token periodically or after inactivity

```javascript
// Refresh token every 30 minutes
setInterval(async () => {
  const response = await fetch('/refresh-csrf');
  const { token } = await response.json();
  document.querySelector('meta[name="csrf-token"]').content = token;
}, 30 * 60 * 1000);
```

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).