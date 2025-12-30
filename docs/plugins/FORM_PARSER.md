# Form Parser Plugin

Parse URL-encoded form data from HTML forms.

## Installation

```ruby
require_relative 'aris/plugins/form_parser'
```

## Basic Usage

```ruby
form = Aris::Plugins::FormParser.build

Aris.routes({
  "example.com": {
    use: [form],
    "/submit": { post: { to: FormHandler } }
  }
})
```

**HTML Form:**
```html
<form action="/submit" method="POST">
  <input name="username" value="alice">
  <input name="email" value="alice@example.com">
  <button type="submit">Submit</button>
</form>
```

**Handler:**
```ruby
class FormHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@form_data)
    
    username = data['username']  #=> "alice"
    email = data['email']        #=> "alice@example.com"
    
    "Welcome, #{username}!"
  end
end
```

---

## How It Works

Parses `application/x-www-form-urlencoded` bodies on POST/PUT/PATCH requests and attaches data to `request.@form_data`.

**Parsed formats:**
- Simple: `name=value&email=test@example.com`
- Nested: `user[name]=alice&user[email]=alice@example.com`
- Arrays: `tags[]=ruby&tags[]=rails`

---

## Common Patterns

### Nested Parameters

```html
<form action="/users" method="POST">
  <input name="user[name]" value="Alice">
  <input name="user[email]" value="alice@example.com">
  <input name="user[age]" value="30">
</form>
```

```ruby
data = request.instance_variable_get(:@form_data)
# {"user" => {"name" => "Alice", "email" => "alice@example.com", "age" => "30"}}

user_data = data['user']
name = user_data['name']  #=> "Alice"
```

### Arrays

```html
<form action="/posts" method="POST">
  <input name="tags[]" value="ruby">
  <input name="tags[]" value="rails">
  <input name="tags[]" value="web">
</form>
```

```ruby
data = request.instance_variable_get(:@form_data)
# {"tags" => ["ruby", "rails", "web"]}

tags = data['tags']  #=> ["ruby", "rails", "web"]
```

### Checkboxes

```html
<form action="/settings" method="POST">
  <input type="checkbox" name="features[]" value="dark_mode" checked>
  <input type="checkbox" name="features[]" value="notifications" checked>
</form>
```

```ruby
features = data['features']  #=> ["dark_mode", "notifications"]
```

### Validation

```ruby
class FormHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@form_data)
    
    unless data && data['email']
      return [400, {}, ['Email required']]
    end
    
    # Process form...
  end
end
```

---

## Behavior

| Request Method | Action |
|:---|:---|
| POST, PUT, PATCH | Parse if content-type matches |
| GET, DELETE | Skip |
| Wrong content-type | Skip |
| Empty body | Skip |

**content-type must be:** `application/x-www-form-urlencoded`

---

## Production Tips

**1. Combine with CSRF Protection**

```ruby
Aris.routes({
  "example.com": {
    use: [:csrf, form_parser],  # CSRF validates, then parse form
    "/submit": { post: { to: FormHandler } }
  }
})
```

**2. Validation**

```ruby
class FormHandler
  REQUIRED = ['name', 'email']
  
  def self.call(request, params)
    data = request.instance_variable_get(:@form_data) || {}
    
    missing = REQUIRED - data.keys
    return [400, {}, ["Missing: #{missing.join(', ')}"]] if missing.any?
    
    # Process...
  end
end
```

**3. Sanitization**

```ruby
def sanitize(data)
  data.transform_values { |v| v.is_a?(String) ? v.strip : v }
end

data = request.instance_variable_get(:@form_data)
clean_data = sanitize(data)
```

---

## Notes

- All values are strings (use `.to_i`, `.to_f` for conversion)
- Uses Rack's built-in parser (battle-tested)
- Nested arrays handled automatically
- No file upload support (use multipart parser for that)

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).