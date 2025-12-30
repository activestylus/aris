# Request Logger Plugin

Log incoming HTTP requests in text or JSON format.

## Installation

```ruby
require_relative 'aris/plugins/request_logger'
```

## Basic Usage

```ruby
logger = Aris::Plugins::RequestLogger.build

Aris.routes({
  "example.com": {
    use: [logger],
    "/users": { get: { to: UsersHandler } }
  }
})
```

**Output (text):**
```
GET /users
POST /users/123
DELETE /users/456
```

---

## Configuration

```ruby
logger = Aris::Plugins::RequestLogger.build(
  format: :json,                    # :text or :json
  exclude: ['/health', '/metrics'], # Skip these paths
  logger: Rails.logger              # Custom logger (default: STDOUT)
)
```

---

## JSON Format

```ruby
logger = Aris::Plugins::RequestLogger.build(format: :json)
```

**Output:**
```json
{"method":"GET","path":"/users","host":"api.example.com","timestamp":"2025-01-10T12:34:56Z"}
{"method":"POST","path":"/users","host":"api.example.com","timestamp":"2025-01-10T12:35:02Z"}
```

---

## Common Patterns

### Exclude Health Checks

```ruby
logger = Aris::Plugins::RequestLogger.build(
  exclude: ['/health', '/ping', '/metrics']
)
```

### Custom Logger

```ruby
# File logger
file_logger = Logger.new('log/requests.log')
logger = Aris::Plugins::RequestLogger.build(logger: file_logger)

# Rails logger
logger = Aris::Plugins::RequestLogger.build(logger: Rails.logger)
```

### Different Logs Per Domain

```ruby
api_logger = Aris::Plugins::RequestLogger.build(
  format: :json,
  logger: Logger.new('log/api.log')
)

admin_logger = Aris::Plugins::RequestLogger.build(
  format: :text,
  logger: Logger.new('log/admin.log')
)

Aris.routes({
  "api.example.com": {
    use: [api_logger],
    "/data": { get: { to: DataHandler } }
  },
  "admin.example.com": {
    use: [admin_logger],
    "/dashboard": { get: { to: DashboardHandler } }
  }
})
```

---

## Production Tips

**1. JSON Format for Log Aggregation**

```ruby
# Works great with ELK, Splunk, CloudWatch
logger = Aris::Plugins::RequestLogger.build(
  format: :json,
  logger: Logger.new(STDOUT)  # Docker captures STDOUT
)
```

**2. Exclude Noisy Endpoints**

```ruby
logger = Aris::Plugins::RequestLogger.build(
  exclude: [
    '/health',
    '/metrics',
    '/favicon.ico',
    '/robots.txt'
  ]
)
```

**3. Log Level**

```ruby
custom_logger = Logger.new(STDOUT)
custom_logger.level = Logger::INFO  # or WARN, ERROR

logger = Aris::Plugins::RequestLogger.build(logger: custom_logger)
```

---

## Limitations

- Logs incoming requests only (no response status/duration)
- For response logging, use Rack middleware or application logs
- No request body logging (use separate middleware for that)

---

Need help? Check out the [full plugin development guide](../docs/plugin-development.md).