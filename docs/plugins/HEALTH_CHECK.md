# Health Check Plugin

Provides a `/health` endpoint for monitoring, load balancers, and orchestration tools (Kubernetes, ECS, etc.). Returns service health status with optional dependency checks.

## Installation

```ruby
require 'aris/plugins/health_check'
```

## Basic Usage

```ruby
health = Aris::Plugins::HealthCheck.build

Aris.routes({
  "api.example.com": {
    use: [health],  # Available at GET /health
    "/users": { get: { to: UsersHandler } }
  }
})

# GET /health
# => { "status": "ok", "name": "app", "checks": {}, "timestamp": "2025-10-10T14:23:45Z" }
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | String | `'/health'` | Health check endpoint path |
| `checks` | Hash | `{}` | Health check functions (name → proc) |
| `name` | String | `'app'` | Service name |
| `version` | String | `nil` | Service version (optional) |

## Examples

### Simple Health Check

```ruby
health = Aris::Plugins::HealthCheck.build

# GET /health
# Response: 200 OK
# {
#   "status": "ok",
#   "name": "app",
#   "checks": {},
#   "timestamp": "2025-10-10T14:23:45Z"
# }
```

### With Database Check

```ruby
health = Aris::Plugins::HealthCheck.build(
  checks: {
    database: -> { 
      ActiveRecord::Base.connection.active? 
    }
  }
)

# GET /health
# Response: 200 OK (if DB healthy)
# {
#   "status": "ok",
#   "name": "app",
#   "checks": {
#     "database": "ok"
#   },
#   "timestamp": "2025-10-10T14:23:45Z"
# }

# Response: 503 Service Unavailable (if DB down)
# {
#   "status": "degraded",
#   "name": "app",
#   "checks": {
#     "database": "fail"
#   },
#   "timestamp": "2025-10-10T14:23:45Z"
# }
```

### Multiple Dependency Checks

```ruby
health = Aris::Plugins::HealthCheck.build(
  name: 'user-api',
  version: '1.2.3',
  checks: {
    database: -> { 
      ActiveRecord::Base.connection.active? 
    },
    redis: -> { 
      Redis.new.ping == 'PONG'
    },
    s3: -> { 
      AWS::S3.new.list_buckets.any?
    }
  }
)

# All healthy: 200 OK
# Any failing: 503 Service Unavailable
```

### Custom Path

```ruby
health = Aris::Plugins::HealthCheck.build(
  path: '/status'
)

# Available at GET /status instead of /health
```

### Kubernetes Liveness Probe

```ruby
health = Aris::Plugins::HealthCheck.build(
  path: '/healthz',
  name: 'my-service'
)

# In kubernetes.yaml:
# livenessProbe:
#   httpGet:
#     path: /healthz
#     port: 3000
#   initialDelaySeconds: 10
#   periodSeconds: 5
```

### AWS ELB Health Check

```ruby
health = Aris::Plugins::HealthCheck.build(
  checks: {
    database: -> { DB.ping }
  }
)

# In ELB config:
# Health check path: /health
# Success codes: 200
# Unhealthy threshold: 2
```

## Check Function Patterns

### Database (ActiveRecord)

```ruby
database: -> { 
  ActiveRecord::Base.connection.active? 
}
```

### Database (Sequel)

```ruby
database: -> { 
  DB.test_connection 
}
```

### Redis

```ruby
redis: -> { 
  Redis.new.ping == 'PONG'
}
```

### External API

```ruby
payment_api: -> {
  response = HTTParty.get('https://api.stripe.com/v1/status')
  response.code == 200
}
```

### File System

```ruby
storage: -> {
  File.writable?('/var/uploads')
}
```

### Memory Usage

```ruby
memory: -> {
  # Check if memory usage is below threshold
  `ps -o rss= -p #{Process.pid}`.to_i < 500_000  # 500MB
}
```

### Custom Logic

```ruby
workers: -> {
  # Check if background workers are running
  Sidekiq::ProcessSet.new.size > 0
}
```

## Response Format

### Healthy Response (200 OK)

```json
{
  "status": "ok",
  "name": "user-api",
  "version": "1.2.3",
  "checks": {
    "database": "ok",
    "redis": "ok"
  },
  "timestamp": "2025-10-10T14:23:45Z"
}
```

### Degraded Response (503 Service Unavailable)

```json
{
  "status": "degraded",
  "name": "user-api",
  "version": "1.2.3",
  "checks": {
    "database": "ok",
    "redis": "fail"
  },
  "timestamp": "2025-10-10T14:23:45Z"
}
```

### Check Exception (503 Service Unavailable)

```json
{
  "status": "degraded",
  "name": "user-api",
  "checks": {
    "database": "error: Connection refused"
  },
  "timestamp": "2025-10-10T14:23:45Z"
}
```

## Production Tips

### 1. Keep Checks Fast

Health checks run on every probe (every 5-10 seconds):

```ruby
# ❌ BAD - Slow query
database: -> { User.count > 0 }

# ✅ GOOD - Fast connection test
database: -> { ActiveRecord::Base.connection.active? }
```

### 2. Separate Liveness vs Readiness

**Liveness:** Is the app alive?
```ruby
liveness = HealthCheck.build(
  path: '/healthz',
  checks: {}  # No dependency checks
)
```

**Readiness:** Is the app ready to serve traffic?
```ruby
readiness = HealthCheck.build(
  path: '/ready',
  checks: {
    database: -> { DB.ping },
    redis: -> { Redis.new.ping == 'PONG' }
  }
)
```

### 3. Timeout Checks

```ruby
require 'timeout'

health = HealthCheck.build(
  checks: {
    database: -> {
      Timeout.timeout(2) do  # 2 second timeout
        ActiveRecord::Base.connection.active?
      end
    rescue Timeout::Error
      false
    }
  }
)
```

### 4. Log Failed Checks

```ruby
health = HealthCheck.build(
  checks: {
    database: -> {
      result = DB.ping
      logger.error("Database health check failed") unless result
      result
    }
  }
)
```

### 5. Monitoring Integration

```ruby
# Send metrics to DataDog/StatsD
health = HealthCheck.build(
  checks: {
    database: -> {
      start = Time.now
      result = DB.ping
      duration = Time.now - start
      
      StatsD.gauge('health.database.duration', duration)
      StatsD.gauge('health.database.status', result ? 1 : 0)
      
      result
    }
  }
)
```

### 6. Security - Internal Only

Don't expose health to public:

```ruby
# Option A: Separate domain
internal_health = HealthCheck.build

Aris.routes({
  "internal.api.com": {  # Internal network only
    use: [internal_health],
    "/admin": { get: { to: AdminHandler } }
  },
  "api.com": {  # Public
    "/users": { get: { to: UsersHandler } }
  }
})

# Option B: IP whitelist
# (Use firewall/load balancer rules)
```

## Common Patterns

### Kubernetes

```yaml
# deployment.yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 10
  
readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
```

```ruby
# health_checks.rb
liveness = HealthCheck.build(path: '/healthz')
readiness = HealthCheck.build(
  path: '/ready',
  checks: {
    database: -> { DB.ping },
    redis: -> { Redis.new.ping == 'PONG' }
  }
)

Aris.routes({
  "api.example.com": {
    use: [liveness, readiness],
    "/users": { get: { to: UsersHandler } }
  }
})
```

### Docker Compose

```yaml
# docker-compose.yml
services:
  api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 3s
      retries: 3
```

### AWS ECS

```json
{
  "healthCheck": {
    "command": ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
    "interval": 30,
    "timeout": 5,
    "retries": 3
  }
}
```

### Uptime Monitoring (Pingdom, UptimeRobot)

```ruby
# Simple endpoint, no dependency checks
health = HealthCheck.build

# Configure monitor:
# URL: https://api.example.com/health
# Expected: 200 OK
# Check frequency: 1 minute
```

## Notes

- Halts plugin pipeline (returns immediately)
- Only responds to GET requests
- Check functions should be fast (<100ms)
- Failed checks return 503 (Service Unavailable)
- Exceptions in checks are caught and reported
- Thread-safe (check functions run synchronously)

## Troubleshooting

**Health check not responding?**
- Verify plugin is in `use:` array
- Check path matches (default: `/health`)
- Ensure GET request (POST won't work)

**Always returns 503?**
- Check which dependency is failing
- Look at `checks` field in response
- Add logging to check functions

**Slow health checks?**
- Profile check functions
- Add timeouts
- Remove expensive checks
- Consider separate liveness/readiness