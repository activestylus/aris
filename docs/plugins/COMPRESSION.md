# Response Compression Plugin

Automatically compresses HTTP responses using gzip to reduce bandwidth usage by 60-80%.

## Installation

```ruby
require 'aris/plugins/compression'
```

## Basic Usage

```ruby
compression = Aris::Plugins::Compression.build

Aris.routes({
  "api.example.com": {
    use: [compression],  # Apply to all routes in domain
    "/data": { get: { to: DataHandler } }
  }
})
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `level` | Integer | `Zlib::DEFAULT_COMPRESSION` | Compression level (0-9, higher = better compression but slower) |
| `min_size` | Integer | `1024` | Minimum response size in bytes to compress |

### Compression Levels

- `Zlib::NO_COMPRESSION` (0) - No compression
- `Zlib::BEST_SPEED` (1) - Fastest, least compression
- `Zlib::DEFAULT_COMPRESSION` (6) - Balanced (default)
- `Zlib::BEST_COMPRESSION` (9) - Slowest, best compression

## Examples

### Default Compression

```ruby
compression = Aris::Plugins::Compression.build

# Compresses responses > 1KB with default level
```

### High Compression

```ruby
compression = Aris::Plugins::Compression.build(
  level: Zlib::BEST_COMPRESSION,  # Maximum compression
  min_size: 512                    # Compress anything > 512 bytes
)
```

### Fast Compression

```ruby
compression = Aris::Plugins::Compression.build(
  level: Zlib::BEST_SPEED,  # Fast compression
  min_size: 2048            # Only compress larger responses
)
```

### Selective Compression

```ruby
# Compress API responses but not static assets
api_compression = Aris::Plugins::Compression.build

Aris.routes({
  "api.example.com": {
    use: [api_compression],
    "/users": { get: { to: UsersHandler } }
  },
  "static.example.com": {
    use: nil,  # No compression for static domain
    "/assets/*path": { get: { to: StaticHandler } }
  }
})
```

## How It Works

1. **Checks client support**: Only compresses if `Accept-Encoding: gzip` header present
2. **Size threshold**: Skips responses smaller than `min_size` (overhead not worth it)
3. **content-type filter**: Only compresses text-based types (JSON, HTML, JS, CSS, XML)
4. **Smart compression**: Skips compression if it makes response larger
5. **Header management**: Sets `Content-Encoding: gzip`, adds `Vary: Accept-Encoding`

## Compressible Content Types

Automatically compresses:
- `text/*` (HTML, CSS, plain text)
- `application/json`
- `application/javascript`
- `application/xml`
- `application/xhtml+xml`

Binary content (images, video, PDFs) is skipped.

## Production Tips

### 1. Tune Compression Level

**High traffic, CPU-bound:**
```ruby
Compression.build(level: Zlib::BEST_SPEED)  # Faster, less CPU
```

**Bandwidth-constrained:**
```ruby
Compression.build(level: Zlib::BEST_COMPRESSION)  # Smaller, more CPU
```

**Balanced (recommended):**
```ruby
Compression.build  # Default level 6
```

### 2. Adjust Minimum Size

Small responses have compression overhead:
```ruby
# Conservative (default)
Compression.build(min_size: 1024)

# Aggressive (compress more)
Compression.build(min_size: 512)

# Very conservative (only large responses)
Compression.build(min_size: 4096)
```

### 3. Order in Plugin Chain

Place **after** plugins that modify body, **before** logging:

```ruby
Aris.routes({
  "api.example.com": {
    use: [
      json_parser,      # Parse request body
      bearer_auth,      # Authenticate
      compression,      # ← Compress response (late in chain)
      request_logger    # Log (sees compressed size)
    ]
  }
})
```

### 4. CDN Compatibility

If using a CDN that compresses:
```ruby
# Let CDN handle it
use: nil

# Or compress at origin for edge caching
compression = Compression.build(level: Zlib::BEST_COMPRESSION)
```

### 5. Monitoring

Track compression ratio:
```ruby
# Before compression
original_size = response.body.join.bytesize

# After compression (in logs)
compressed_size = response.body.first.bytesize

ratio = (1 - compressed_size.to_f / original_size) * 100
# Typical: 70-80% reduction for JSON/text
```

## Benchmarks

Typical compression ratios:
- JSON APIs: 75-85% reduction
- HTML pages: 65-75% reduction  
- JavaScript: 60-70% reduction
- Plain text: 50-70% reduction

Performance impact:
- Level 1: ~0.1ms overhead per response
- Level 6: ~0.5ms overhead per response
- Level 9: ~2ms overhead per response

*Based on 10KB responses. YMMV.*

## Notes

- Compression happens in-memory (entire response buffered)
- Already-compressed content (images, video) is skipped automatically
- `Content-Length` header is removed (server recalculates)
- `Vary: Accept-Encoding` header ensures proper caching
- Thread-safe (no shared state)

## Troubleshooting

**Compression not working?**
- Check `Accept-Encoding` header includes `gzip`
- Verify response is > `min_size`
- Confirm `content-type` is compressible
- Check if compression actually saves space

**High CPU usage?**
- Lower compression level: `level: Zlib::BEST_SPEED`
- Increase minimum size: `min_size: 2048`
- Profile with different levels

**Wrong compressed output?**
- Ensure no plugins modify body after compression
- Verify no double-compression (CDN + origin)