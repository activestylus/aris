# Changelog

## [1.4.0] - 2025-12-30
This release adds native static file serving with production-grade MIME type handling.

### ✨ Added
* **Static File Serving:** Introduced `Aris::Config.serve_static` to serve static assets directly from the `public/` directory in development. Works seamlessly with nginx in production (nginx handles static files, Aris handles dynamic routes).
* **Configurable MIME Types:** Added `Aris::Config.mime_types` with sensible defaults for common file types (images, fonts, CSS, JS). Fully extensible for custom file formats.
* **Cache Headers:** Static files are served with `Cache-Control: public, max-age=31536000` for optimal browser caching.

### 🔧 Changed
* Both `RackApp` and `MockAdapter` now check for static files before routing, improving performance for asset-heavy applications.

### 📝 Usage
```ruby
# Enable in development (disabled by default)
Aris.configure do |c|
  c.serve_static = ENV['RACK_ENV'] != 'production'
  
  # Optional: Add custom MIME types
  c.mime_types = {
    '.webm' => 'video/webm',
    '.flac' => 'audio/flac'
  }
end
```

## [1.3.0] - 2025-12-30

This release focuses on state management and fine-tuning URL strictness.

### ✨ Added

* **Session & Flash Support:** Introduced `Aris::Plugins::Session` and `Aris::Plugins::Flash`. Supports persistence across redirects and "flash.now" for the current request cycle.
* **Trailing Slash Configuration:** Added `Aris::Config.trailing_slash`. You can now choose between `:strict` (default), `:ignore`, or `:redirect` (301/302) to normalize incoming paths.
* **Cookie Management:** Added `Aris::Plugins::Cookies` with a fluent helper API for reading, writing, and deleting cookies with secure defaults.

### 🐛 Fixed

* Fixed a bug where the `MockAdapter` would not correctly pass the response object into handler blocks, causing issues with state-dependent plugins.

---

## [1.2.0] - 2025-12-15

Deep integration for internationalization and complex domain patterns.

### ✨ Added

* **First-Class Locales:** Added `Aris::LocaleInjector`. Routes can now be expanded per-locale (e.g., `/en/about` and `/es/acerca` pointing to the same handler).
* **Locale-Aware Path Generation:** `Aris.path` now accepts a `locale:` argument to generate localized URLs automatically.
* **Root Locale Redirect:** Added `root_locale_redirect: true` to domain configurations to automatically bounce users from `/` to their default locale.
* **Subdomain Wildcards:** Enhanced the Trie to support `*.example.com` routing. The `request.subdomain` helper now correctly extracts multi-level subdomains (e.g., "app.staging").

### 💥 Changed

* **Response Helpers:** Refactored `Aris::Response` into a modular helper system. Handlers now have access to `res.json`, `res.html`, `res.text`, and `res.xml`.

---

## [1.1.0] - 2025-11-20

Introduction of the "Utils" layer for SEO and automated metadata.

### ✨ Added

* **Sitemap Generator:** Added `Aris::Utils::Sitemap`. Automatically generates `sitemap.xml` based on discovered routes and provided metadata (priority, changefreq).
* **Redirects Manager:** Added `Aris::Utils::Redirects`. Allows registering legacy URL mappings directly within route handlers using the `redirects_from` helper.
* **Content Negotiation:** Added `res.negotiate`. Handlers can now respond to different formats (JSON, XML, HTML) using a single block.

### 💥 Changed

* **Header Normalization:** Aris now internally downcases all header keys to ensure compatibility between different Rack servers and the Mock adapter.

---

## [1.0.0] - 2025-10-30

The "Autodiscovery" Milestone. This version marks the transition to a file-based convention for large-scale applications.

### ✨ Added

* **Route Autodiscovery:** Introduced `Aris.discover_and_define(routes_dir)`. Aris now scans your directory structure (e.g., `domain/path/_id/get.rb`) to build the routing tree automatically.
* **Convention-over-Configuration:** Parameterized routes are now identified by the `_` prefix in the filesystem (e.g., `_slug` becomes `:slug`).
* **OpenAPI/Swagger Metadata:** Added `api_doc` helper to handlers to facilitate automatic documentation generation.

### 💥 Changed

* **Handler Resolution:** The `PipelineRunner` now lazily loads `Handler` constants from Ruby files only when the route is matched, significantly reducing boot time for thousands of routes.

---

## [0.9.0] - 2025-10-05

Performance optimization and production hardening.

### ✨ Added

* **Request ID Tracking:** Added `Aris::Plugins::RequestId`. Automatically preserves or generates `X-Request-ID` headers for distributed tracing.
* **Response Compression:** Added `Aris::Plugins::Compression`. Transparent Gzip compression for text-based responses over a configurable size threshold.
* **Security Headers:** Added `Aris::Plugins::SecurityHeaders`. Configurable defaults for HSTS, CSP, X-Frame-Options, and Referrer-Policy.

### ⚡ Performance

* Optimized Trie traversal by caching path segments, resulting in a 15% speed increase for deeply nested routes.

---

## [0.8.0] - 2025-09-10

Advanced matching features.

### ✨ Added

* **Path Constraints:** Added `constraints: { id: /\d+/ }` support. Routes now only match if parameters satisfy the provided regex.
* **Wildcard Globbing:** Added support for `*path` segments to capture remaining path parts into a single parameter.
* **Health Checks:** Added `Aris::Plugins::HealthCheck`. A highly configurable plugin for liveness/readiness probes with dependency monitoring.

---

## [0.7.0] - 2025-08-15

Middleware and the Plugin Pipeline.

### ✨ Added

* **The Plugin System:** Introduced the `use:` key at domain, scope, and route levels. Plugins follow a `call(request, response)` contract.
* **JSON Body Parser:** Added `Aris::Plugins::Json` to automatically parse incoming payloads into `request.json_body`.
* **Form Parser:** Added support for `application/x-www-form-urlencoded` payloads via `Aris::Plugins::FormParser`.

---

## [0.6.0] - 2025-07-20

Hardened Authentication.

### ✨ Added

* **Bearer Auth Plugin:** Standardized token-based authentication.
* **Basic Auth Plugin:** Easy username/password protection for admin scopes.
* **API Key Auth Plugin:** Header-based key validation with custom validator support.
* **CORS Plugin:** Full support for origins, methods, credentials, and preflight `OPTIONS` handling.

---

## [0.5.0] - 2025-06-28

Integrated CSRF and Mocking.

### ✨ Added

* **CSRF Protection:** A two-phase plugin (`CsrfTokenGenerator` and `CsrfProtection`) to secure state-changing requests.
* **Mock Adapter:** Built `Aris::Adapters::Mock` to allow full integration testing of routes and plugins without a live Rack server.

---

## [0.4.0] - 2025-06-01

The "Rack" release.

### ✨ Added

* **Rack Adapter:** Official production adapter `Aris::Adapters::RackApp`.
* **Agnostic Request/Response:** Wrapped Rack environment in `Aris::Request` and `Aris::Response` to ensure handlers remain server-agnostic.

---

## [0.3.0] - 2025-05-15

Named routes and URL generation.

### ✨ Added

* **Named Routes:** Added the `as:` option to route definitions.
* **Path/URL Helpers:** Introduced `Aris.path` and `Aris.url`. Support for query parameter appending and automatic URI encoding.
* **Domain Context:** Added `Aris.with_domain` for scoped URL generation.

---

## [0.2.0] - 2025-04-25

Multi-domain support.

### ✨ Added

* **Multi-Domain Routing:** The routing hash now accepts domain strings as top-level keys.
* **Wildcard Domain Fallback:** Support for the `"*"` domain key to handle health checks or generic responses across all hosts.

---

## [0.1.0] - 2025-04-10

### ✨ Added

* **Initial Release!**
* Core Trie-based routing engine.
* Support for standard HTTP verbs (GET, POST, PUT, PATCH, DELETE).
* Parameter extraction (e.g., `/users/:id`).
* Global `Aris.routes` configuration.

---

**Would you like me to ...**

* Generate the `VERSION` file for this project?
* Create a `ROADMAP.md` for 2026?
* Implement a CLI command to auto-generate this changelog from git tags?