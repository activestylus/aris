# JSON Body Parser Plugin

Automatically parse JSON request bodies and attach parsed data to the request object.

## Installation

```ruby
# lib/aris.rb already includes this
require_relative 'aris/plugins/json'
```

## How It Works

Runs on POST/PUT/PATCH requests. Reads `rack.input`, parses JSON, and attaches to `request.json_body`. Returns **400 Bad Request** on invalid JSON.

---

## Basic Usage

```ruby
Aris.routes({
  "api.example.com": {
    use: [:json],
    "/users": { post: { to: CreateUserHandler } }
  }
})
```

**Handler access:**

```ruby
class CreateUserHandler
  def self.call(request, params)
    data = request.json_body
    
    User.create(
      name: data['name'],
      email: data['email']
    )
    
    { success: true, user_id: user.id }
  end
end
```

**Request:**
```bash
curl -X POST https://api.example.com/users \
  -H "content-type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com"}'
```

---

## Error Handling

**Invalid JSON returns 400:**

```bash
curl -X POST https://api.example.com/users \
  -H "content-type: application/json" \
  -d '{invalid json}'
```

**Response:**
```json
{
  "error": "Invalid JSON",
  "message": "unexpected token at '{invalid json}'"
}
```

---

## Behavior

| Request Method | Action |
|:---|:---|
| POST, PUT, PATCH | Parse JSON body |
| GET, DELETE, HEAD | Skip (no action) |
| Empty body | Skip (no action) |
| Invalid JSON | Halt with 400 error |

**Parsed data available at:**
```ruby
request.json_body  # Hash or Array
```

---

## Common Patterns

### Combine with Validation

```ruby
class CreateUserHandler
  def self.call(request, params)
    data = request.json_body
    
    # Validate required fields
    unless data['name'] && data['email']
      return [400, {}, [JSON.generate({ error: 'Missing required fields' })]]
    end
    
    User.create(data)
  end
end
```

### Nested JSON

```ruby
# Request body
{
  "user": {
    "name": "Alice",
    "address": {
      "city": "New York",
      "zip": "10001"
    }
  }
}

# Handler
data = request.json_body
name = data['user']['name']
city = data['user']['address']['city']
```

### JSON Arrays

```ruby
# Request: [{"name": "Alice"}, {"name": "Bob"}]

data = request.json_body  # Array
data.each do |user|
  User.create(name: user['name'])
end
```

---

## Plugin Order

Place JSON parser **early** in the pipeline:

```ruby
Aris.routes({
  "api.example.com": {
    use: [:json, :csrf, bearer_auth],  # Parse first
    "/users": { post: { to: CreateUserHandler } }
  }
})
```

**Why?** Subsequent plugins or handlers may need access to `request.json_body`.

---

## Testing

```ruby
class JsonParserTest < Minitest::Test
  def test_valid_json_parsed
    Aris.routes({
      "api.test": {
        use: [:json],
        "/data": { post: { to: DataHandler } }
      }
    })
    
    app = Aris::Adapters::RackApp.new
    body = JSON.generate({ name: 'Alice' })
    
    env = {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/data',
      'HTTP_HOST' => 'api.test',
      'rack.input' => StringIO.new(body)
    }
    
    status, _, response = app.call(env)
    assert_equal 200, status
  end
  
  def test_invalid_json_returns_400
    # Same setup...
    env['rack.input'] = StringIO.new('{invalid}')
    
    status, _, response = app.call(env)
    assert_equal 400, status
    
    error = JSON.parse(response.first)
    assert_equal 'Invalid JSON', error['error']
  end
end
```

---

## Production Tips

**1. content-type Validation**

Currently parses regardless of content-type. For strict APIs:

```ruby
class StrictJsonParser
  def self.call(request, response)
    return nil unless ['POST', 'PUT', 'PATCH'].include?(request.method)
    
    # Require correct content-type
    content_type = request.headers['CONTENT_TYPE']
    unless content_type&.include?('application/json')
      response.status = 415
      response.body = ['Unsupported Media Type']
      return response
    end
    
    # Parse JSON...
  end
end
```

**2. Size Limits**

Protect against large payloads:

```ruby
MAX_BODY_SIZE = 1_000_000  # 1MB

def call(request, response)
  raw_body = request.body
  
  if raw_body.bytesize > MAX_BODY_SIZE
    response.status = 413
    response.body = ['Payload Too Large']
    return response
  end
  
  # Parse JSON...
end
```

**3. Schema Validation**

Use JSON Schema for validation:

```ruby
require 'json-schema'

class ValidatedJsonParser
  SCHEMA = {
    "type" => "object",
    "required" => ["name", "email"],
    "properties" => {
      "name" => { "type" => "string" },
      "email" => { "type" => "string", "format" => "email" }
    }
  }
  
  def self.call(request, response)
    # Parse JSON first...
    data = JSON.parse(request.body)
    
    # Validate against schema
    errors = JSON::Validator.fully_validate(SCHEMA, data)
    if errors.any?
      response.status = 422
      response.body = [JSON.generate({ errors: errors })]
      return response
    end
    
    request.json_body = data
    nil
  end
end
```

---

## Notes

- **Only parses POST/PUT/PATCH** - GET requests ignored
- **Empty bodies skipped** - No error, just continues
- **Thread-safe** - Each request has isolated `json_body`
- **No streaming** - Reads entire body into memory

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).