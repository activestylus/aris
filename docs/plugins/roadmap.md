
---

### 10. HTTP Method Override

**Configuration:**
```ruby
Aris.configure do |config|
  config.method_override = true  # Enable _method parameter
end
```

**Form Usage:**
```html
<!-- Old browser - only supports GET/POST -->
<form action="/users/123" method="POST">
  <input type="hidden" name="_method" value="DELETE">
  <button type="submit">Delete User</button>
</form>
```

**Request Processing:**
```ruby
# POST /users/123?_method=DELETE
# Automatically converted to:
# DELETE /users/123

class UserDeleteHandler
  def self.call(request, response)
    # Receives as DELETE request
    request.method  # => "DELETE" (not "POST")
    
    User.destroy(request.params[:id])
    response.redirect_to(:users)
  end
end
```

**How it feels:**
- Enable once in config
- Works automatically
- Handler sees correct method

---

### 11. Route Aliases

**Route Definition:**
```ruby
Aris.routes({
  "example.com": {
    # Multiple paths to same handler
    ["/about", "/about-us", "/company"]: {
      get: { to: AboutHandler, as: :about }
    },
    
    # Or using aliases key
    "/contact": {
      get: { 
        to: ContactHandler,
        as: :contact,
        aliases: ["/contact-us", "/get-in-touch"]
      }
    }
  }
})
```

**Behavior:**
```ruby
# All these work:
GET /about       → AboutHandler
GET /about-us    → AboutHandler  
GET /company     → AboutHandler

# URL generation uses canonical (as: name)
Aris.path(:about)  # => "/about" (first in array)
```

**How it feels:**
- Array syntax for multiple paths
- Or `aliases:` key
- Clean, obvious

---

### 12. Global Default Params

**Configuration:**
```ruby
Aris.configure do |config|
  config.default_params = {
    api_version: 'v1',
    format: 'json'
  }
end
```

**Handler Usage:**
```ruby
class UserHandler
  def self.call(request, response)
    # Default params automatically merged
    version = request.params[:api_version]  # => "v1"
    format = request.params[:format]        # => "json"
    
    # Can be overridden by route params
    id = request.params[:id]
  end
end
```

**How it feels:**
- Set once globally
- Available in all handlers
- Can be overridden by actual params

---

## 🎨 Complete Example: User CRUD

Here's what a complete handler looks like with all features:

```ruby
class UserCreateHandler
  def self.call(request, response)
    # I18n
    locale = request.locale  # => :en
    
    # Params from POST body (JSON plugin parsed it)
    user_params = request.params[:user]
    
    # Session
    current_user_id = request.session[:user_id]
    
    # Create user
    user = User.create(user_params)
    
    if user.valid?
      # Flash message
      request.flash[:notice] = "User created successfully!"
      
      # Signed cookie
      request.signed_cookies[:last_created_user] = user.id
      
      # Redirect
      response.redirect_to(:user_show, id: user.id)
    else
      # Flash.now
      request.flash.now[:error] = "Validation failed"
      
      # Content negotiation
      case request.format
      when :json
        response.json({ errors: user.errors }, status: 422)
      when :html
        response.html(form_template(user), status: 422)
      end
    end
  end
end
```

**How it feels:**
- Everything scoped to `request` or `response`
- No magic methods appearing from nowhere
- Clear data flow
- Explicit framework usage
- Fast (minimal allocation)

---

## Summary: The Aris Way™

**Request-scoped:**
- `request.locale` - i18n
- `request.format` - content negotiation
- `request.flash` - flash messages
- `request.session` - session data
- `request.cookies` / `request.signed_cookies` / `request.encrypted_cookies`
- `request.subdomain` - subdomain capture
- `request.params` - route + query + body params

**Response-scoped:**
- `response.json(data, status:)`
- `response.html(content, status:)`
- `response.xml(data, status:)`
- `response.redirect_to(path, status:)`
- `response.text(string, status:)`
- `response.send_file(path)`
- `response.no_content`

**Module-level (framework utilities):**
- `Aris.path(name, **params)` - URL generation
- `Aris.redirect(target, status:)` - redirect tuple
- `Aris.configure` - configuration
- `Aris::Utils::Sitemap` - sitemap generation
- `Aris::Utils::Redirects` - redirect management

---