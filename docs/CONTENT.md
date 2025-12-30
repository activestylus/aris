# Aris Content - Complete Specification

## Overview

**aris-content** is a companion gem for **aris** that provides content intelligence and SEO utilities for multi-domain, static-first Ruby sites. It operates in two silos:

1. **Hub** - Development-time feedback, metrics, and insights
2. **Generators** - Production-ready SEO utilities (sitemap, robots, meta, schema)

**Philosophy:**
- Declarative at the handler level
- Zero performance impact on production requests
- Works with both file-based discovery and hash-based routes
- Unix philosophy: optional, composable, focused

---

## Installation

```ruby
# Gemfile
gem 'aris'          # Core router
gem 'aris-content'  # Content intelligence

# Auto-loads and extends Aris with content features
```

---

## SILO 1: Hub (Development Intelligence)

### Architecture

- SQLite database (`.aris/content.db`) - gitignored
- Git integration for freshness tracking
- File watcher for live updates
- Separate Rack server for dashboard
- Zero impact on main app performance

### Features

#### 1. Content Indexer
Scans all routes (discovered + hash-based) and extracts:
- Domain, path, method
- Handler metadata (meta, sitemap, schema, redirects)
- Content analysis (word count, keywords, headings)
- Performance metrics (HTML size, image count)
- Link structure (internal/external)

#### 2. Health Score
Aggregate score (0-100) based on:
- Meta tags present
- Content freshness
- Performance budgets met
- Link graph health
- Image optimization
- Heading structure

#### 3. Freshness Tracker
Uses Git to track:
- Last updated timestamp
- Author of last change
- Commit history
- Time since last update
- Stale content warnings (configurable threshold)

#### 4. Performance Budgets
Tracks and warns:
- HTML size
- Total page weight
- Image count/size
- External requests
- Custom metrics

#### 5. Link Graph Analysis
- Internal link structure
- Orphaned pages (no incoming links)
- Deep pages (5+ clicks from home)
- Broken internal links
- Most/least linked pages
- Link graph visualization

#### 6. SEO Validation
- Missing meta tags
- Duplicate titles/descriptions
- Heading hierarchy issues (H1/H2/H3)
- Image alt text missing
- Canonical issues
- Schema.org validation

#### 7. Content Analysis
- Word count
- Reading time
- Keyword extraction & frequency
- Top keywords per page
- Content comparison tool

#### 8. Dashboard Server
- Clean HTML interface (Alpine.js for interactivity)
- Issue list (critical/warning/info)
- Per-page detail views
- Quick wins recommendations
- Auto-refresh on file changes
- Export to JSON

---

### Hub CLI Commands

```bash
# Start dashboard server
$ aris content hub
🚀 Content Hub starting...
📊 Dashboard: http://localhost:4000
🔍 Analyzing 247 pages across 3 domains...
✅ Ready in 2.1s

# Quick status check
$ aris content status
Health Score: 87/100
Critical Issues: 4
Warnings: 12
Pages: 247

# List stale content
$ aris content stale
/blog/old-post (18 months ago)
/about/team (14 months ago)
/services/legacy (9 months ago)

# Find orphaned pages
$ aris content orphans
/hidden/page (0 incoming links)
/test/sandbox (0 incoming links)

# Performance budget check
$ aris content budgets
❌ /blog/post-1 (89kb > 50kb budget)
⚠️  /products (52kb > 50kb budget)
✅ 245 pages within budget

# Export data
$ aris content export --format json > content-report.json

# Compare two pages
$ aris content compare /blog/post-1 /blog/post-2
Word count:     1,234 vs 456
Keywords:       ruby(12) vs rails(8)
Links out:      5 vs 2
Images:         3 vs 1
Read time:      6min vs 2min
```

---

### Hub Configuration

```ruby
# config/aris_content.rb
Aris::Content.configure do |config|
  # Performance budgets
  config.performance_budget do |budget|
    budget.max_html_size = 50.kilobytes
    budget.max_images = 10
    budget.max_external_requests = 20
  end
  
  # Freshness thresholds
  config.freshness_threshold = 6.months
  config.freshness_warning = 3.months
  
  # Target keywords per domain
  config.target_keywords "example.com", %w[ruby router performance seo]
  config.target_keywords "shop.example.com", %w[products ecommerce checkout]
  
  # Dashboard settings
  config.dashboard_port = 4000
  config.dashboard_refresh_interval = 5.seconds
  
  # Exclude paths from analysis
  config.exclude_paths %w[/admin /api/internal /test]
end
```

---

## SILO 2: Generators (SEO Utilities)

### 1. Sitemap Generator

#### Handler DSL

```ruby
# File-based route
module Handler
  extend Aris::RouteHelpers
  
  sitemap(
    priority: 0.8,
    changefreq: 'weekly',
    lastmod: '2025-01-15'
  )
  
  def self.call(request, params)
    # ...
  end
end
```

#### Dynamic Sitemap (Multiple URLs per Route)

```ruby
sitemap do
  # Return array of URL data
  Post.all.map do |post|
    {
      path: "/blog/#{post.slug}",
      priority: post.featured? ? 1.0 : 0.7,
      changefreq: 'daily',
      lastmod: post.updated_at
    }
  end
end
```

#### Hash-based Routes

```ruby
Aris.routes({
  "example.com": {
    "/": { 
      get: { 
        to: HomeHandler,
        sitemap: { priority: 1.0, changefreq: 'daily' }
      }
    },
    "/about": {
      get: {
        to: AboutHandler,
        sitemap: { priority: 0.8, changefreq: 'monthly' }
      }
    }
  }
})
```

#### Auto-serves `/sitemap.xml`

```xml
GET /sitemap.xml

<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/</loc>
    <lastmod>2025-01-15</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://example.com/about</loc>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
</urlset>
```

---

### 2. Robots.txt Generator

#### Handler DSL

```ruby
robots(
  allow: ["/", "/blog/*"],
  disallow: ["/admin", "/api/*", "/private"],
  crawl_delay: 1
)
```

#### Domain-level Configuration

```ruby
Aris::Content::Robots.configure do |config|
  config.domain "example.com" do
    allow ["/", "/blog/*", "/products/*"]
    disallow ["/admin", "/private"]
    sitemap "https://example.com/sitemap.xml"
  end
  
  config.domain "staging.example.com" do
    disallow ["/"]  # Block all on staging
  end
end
```

#### Auto-serves `/robots.txt`

```
GET /robots.txt

User-agent: *
Allow: /
Allow: /blog/*
Disallow: /admin
Disallow: /api/*
Crawl-delay: 1

Sitemap: https://example.com/sitemap.xml
```

---

### 3. Meta Tags Manager

#### Handler DSL

```ruby
meta(
  title: "Best Ruby Framework 2025",
  description: "Deploy sites across multiple domains with lightning speed",
  keywords: %w[ruby router framework multi-domain],
  
  # Open Graph
  og_title: "Custom OG Title",
  og_description: "Custom OG Description",
  og_image: "/images/og-hero.jpg",
  og_type: "website",
  
  # Twitter Card
  twitter_card: "summary_large_image",
  twitter_site: "@example",
  twitter_creator: "@author",
  
  # SEO
  canonical: true,  # Auto-generates from current path
  robots: "index, follow"
)
```

#### Dynamic Meta

```ruby
meta do
  {
    title: "#{@product.name} | Example Store",
    description: @product.description.truncate(160),
    og_image: @product.image_url,
    og_type: "product"
  }
end
```

#### Hash-based Routes

```ruby
Aris.routes({
  "example.com": {
    "/": {
      get: {
        to: HomeHandler,
        meta: {
          title: "Welcome Home",
          description: "...",
          og_image: "/hero.jpg"
        }
      }
    }
  }
})
```

#### Rendering in Layout

```erb
<!-- layout.html.erb -->
<head>
  <%= Aris::Content::Meta.render %>
</head>
```

**Outputs:**

```html
<title>Best Ruby Framework 2025</title>
<meta name="description" content="Deploy sites across multiple domains...">
<meta name="keywords" content="ruby, router, framework, multi-domain">

<meta property="og:title" content="Custom OG Title">
<meta property="og:description" content="Custom OG Description">
<meta property="og:image" content="https://example.com/images/og-hero.jpg">
<meta property="og:type" content="website">
<meta property="og:url" content="https://example.com/current-page">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="@example">
<meta name="twitter:creator" content="@author">

<link rel="canonical" href="https://example.com/current-page">
<meta name="robots" content="index, follow">
```

---

### 4. Structured Data (Schema.org)

#### Handler DSL

```ruby
schema(
  type: "Article",
  headline: "My Amazing Blog Post",
  author: {
    "@type": "Person",
    name: "John Doe"
  },
  datePublished: "2025-01-15",
  dateModified: "2025-01-20",
  image: "/images/post-hero.jpg",
  publisher: {
    "@type": "Organization",
    name: "Example Company",
    logo: "/logo.png"
  }
)
```

#### Dynamic Schema

```ruby
schema do
  {
    "@type": "Product",
    name: @product.name,
    description: @product.description,
    image: @product.image_url,
    offers: {
      "@type": "Offer",
      price: @product.price,
      priceCurrency: "USD",
      availability: @product.in_stock? ? "InStock" : "OutOfStock"
    }
  }
end
```

#### Built-in Templates

```ruby
schema :article do |s|
  s.headline = "My Post"
  s.author = "John Doe"
  s.date_published = "2025-01-15"
end

schema :product do |s|
  s.name = @product.name
  s.price = @product.price
  s.image = @product.image_url
end

schema :organization do |s|
  s.name = "Example Company"
  s.url = "https://example.com"
  s.logo = "/logo.png"
  s.social_profiles = [
    "https://twitter.com/example",
    "https://facebook.com/example"
  ]
end
```

#### Rendering in Layout

```erb
<head>
  <%= Aris::Content::Schema.render %>
</head>
```

**Outputs:**

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "My Amazing Blog Post",
  "author": {
    "@type": "Person",
    "name": "John Doe"
  },
  "datePublished": "2025-01-15",
  "dateModified": "2025-01-20",
  "image": "https://example.com/images/post-hero.jpg",
  "publisher": {
    "@type": "Organization",
    "name": "Example Company",
    "logo": "https://example.com/logo.png"
  }
}
</script>
```

---

### 5. RSS/Atom Feed Generator

#### Configuration

```ruby
Aris::Content::Feed.configure do |config|
  config.domain "example.com" do
    title "Example Blog"
    description "Latest posts from Example"
    link "https://example.com"
    
    items do
      Post.recent(20).map do |post|
        {
          title: post.title,
          link: "https://example.com/blog/#{post.slug}",
          description: post.excerpt,
          pubDate: post.published_at,
          guid: post.id
        }
      end
    end
  end
end
```

#### Auto-serves `/feed.xml`

```xml
GET /feed.xml

<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example Blog</title>
    <link>https://example.com</link>
    <description>Latest posts from Example</description>
    <item>
      <title>My Blog Post</title>
      <link>https://example.com/blog/my-post</link>
      <description>Post excerpt...</description>
      <pubDate>Mon, 15 Jan 2025 10:00:00 GMT</pubDate>
      <guid>123</guid>
    </item>
  </channel>
</rss>
```

#### Auto-injects Feed Link

```html
<head>
  <link rel="alternate" type="application/rss+xml" 
        title="Example Blog" 
        href="https://example.com/feed.xml">
</head>
```

---

### 6. Breadcrumbs Generator

#### Handler DSL

```ruby
breadcrumbs auto: true  # Generates from route structure

# Or custom
breadcrumbs [
  { name: "Home", url: "/" },
  { name: "Blog", url: "/blog" },
  { name: "My Post" }  # Current page, no URL
]
```

#### Rendering

```erb
<%= Aris::Content::Breadcrumbs.render %>
```

**Outputs:**

```html
<nav aria-label="breadcrumb">
  <ol itemscope itemtype="https://schema.org/BreadcrumbList">
    <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem">
      <a itemprop="item" href="/">
        <span itemprop="name">Home</span>
      </a>
      <meta itemprop="position" content="1">
    </li>
    <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem">
      <a itemprop="item" href="/blog">
        <span itemprop="name">Blog</span>
      </a>
      <meta itemprop="position" content="2">
    </li>
    <li itemprop="itemListElement" itemscope itemtype="https://schema.org/ListItem">
      <span itemprop="name">My Post</span>
      <meta itemprop="position" content="3">
    </li>
  </ol>
</nav>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [...]
}
</script>
```

---

## Integration with Aris Core

### Automatic Hook Points

```ruby
# In aris-content, automatically extends:

# 1. RouteHelpers module
module Aris::RouteHelpers
  # Adds: sitemap, meta, schema, robots, breadcrumbs methods
end

# 2. Discovery system
module Aris::Discovery
  # Hooks into add_route_to_hash to register metadata
end

# 3. Compiler
module Aris
  # Hooks into routes() to extract metadata from hash routes
end

# 4. Base adapter
module Aris::Adapters::Base
  # Adds: handle_sitemap, handle_robots, handle_feed methods
end
```

### Zero Configuration Required

```ruby
# Just require the gem
require 'aris/content'

# Everything works automatically:
# - Handlers can use sitemap/meta/schema
# - /sitemap.xml auto-serves
# - /robots.txt auto-serves
# - /feed.xml auto-serves
# - Hub commands available
```

---

## Production Metrics (Optional Plugin)

### Opt-in Tracking

```ruby
# Gemfile
gem 'aris-content', require: ['aris/content', 'aris/content/metrics']

# config.ru (production)
use Aris::Content::MetricsCollector,
  storage: './metrics.db',
  sample_rate: 0.1  # Track 10% of requests

run Aris::Adapters::RackApp.new
```

### What's Tracked (Minimal, Privacy-Focused)

- Path
- Domain
- Status code
- Response time
- Timestamp
- **NO user data, NO IP addresses, NO PII**

### Pull to Dev

```bash
# Export from production
$ aris content export-metrics > metrics.json

# Import to dev
$ aris content import-metrics metrics.json

# Dashboard now shows production data
```

**Hub Dashboard with Production Data:**

```
TOP PAGES (Last 30 Days)

Production Data: ✓

Path                    Views     Avg Time    Health
/                       45,231    120ms       ✅ 95
/blog/popular-post      12,450    340ms       ⚠️  72
/products               8,932     890ms       ❌ 45 (slow!)
```

---

## Developer Experience Examples

### Example 1: Blog Post with Full SEO

```ruby
# app/routes/example.com/blog/:slug/get.rb
module Handler
  extend Aris::RouteHelpers
  
  # Sitemap
  sitemap do
    Post.published.map do |post|
      {
        path: "/blog/#{post.slug}",
        priority: post.featured? ? 1.0 : 0.7,
        changefreq: 'weekly',
        lastmod: post.updated_at
      }
    end
  end
  
  # Meta tags
  meta do
    {
      title: "#{@post.title} | Example Blog",
      description: @post.excerpt.truncate(160),
      keywords: @post.tags,
      og_image: @post.hero_image_url,
      og_type: "article",
      twitter_card: "summary_large_image"
    }
  end
  
  # Structured data
  schema :article do |s|
    s.headline = @post.title
    s.author = @post.author.name
    s.date_published = @post.published_at
    s.date_modified = @post.updated_at
    s.image = @post.hero_image_url
  end
  
  # Breadcrumbs
  breadcrumbs [
    { name: "Home", url: "/" },
    { name: "Blog", url: "/blog" },
    { name: @post.title }
  ]
  
  def self.call(request, params)
    @post = Post.find_by_slug(params[:slug])
    render :blog_post
  end
end
```

### Example 2: Product Page

```ruby
# app/routes/shop.example.com/products/:id/get.rb
module Handler
  extend Aris::RouteHelpers
  
  sitemap(priority: 0.8, changefreq: 'daily')
  
  meta do
    {
      title: "#{@product.name} - $#{@product.price}",
      description: @product.description,
      og_type: "product",
      og_image: @product.primary_image_url
    }
  end
  
  schema :product do |s|
    s.name = @product.name
    s.description = @product.description
    s.image = @product.images.map(&:url)
    s.offers do
      {
        "@type": "Offer",
        price: @product.price,
        priceCurrency: "USD",
        availability: @product.in_stock? ? "InStock" : "OutOfStock"
      }
    end
  end
  
  def self.call(request, params)
    @product = Product.find(params[:id])
    render :product
  end
end
```

### Example 3: Simple Page (Hash Routes)

```ruby
Aris.routes({
  "example.com": {
    "/about": {
      get: {
        to: AboutHandler,
        sitemap: { priority: 0.8, changefreq: 'monthly' },
        meta: {
          title: "About Us",
          description: "Learn about our company",
          og_image: "/images/about-hero.jpg"
        }
      }
    }
  }
})
```

---

## Dashboard Preview

```
╔════════════════════════════════════════════════════════╗
║  CONTENT HEALTH SCORE: 87/100                         ║
║  Last updated: 3 seconds ago                          ║
╚════════════════════════════════════════════════════════╝

🔴 CRITICAL ISSUES (4)

  /blog/old-post (example.com)
  ├─ Not updated in 18 months
  ├─ No internal links to this page
  ├─ Missing meta description
  └─ [View Details] [Mark Reviewed]

  /products/widget (shop.example.com)
  ├─ HTML size: 89kb (budget: 50kb)
  ├─ 3 images without alt text
  ├─ hero.jpg is 2.1MB (not optimized)
  └─ [View Details] [Ignore]

⚠️  WARNINGS (12)

  /about/team (example.com)
  ├─ Title is short (15 chars, recommend 50-60)
  ├─ Last updated 5 months ago
  └─ [View Details]

✅ HEALTHY (231 pages)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QUICK WINS (Easy fixes, high impact)

1. Add meta descriptions (8 pages)
2. Optimize large images (12 images)
3. Fix duplicate titles (3 pages)
4. Link to orphaned pages (3 pages)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PERFORMANCE BUDGETS

example.com
├─ / ...................... ✅ 24kb (budget: 50kb)
├─ /about ................. ✅ 31kb (budget: 50kb)
├─ /blog/post-1 ........... ❌ 89kb (budget: 50kb)
└─ /contact ............... ✅ 18kb (budget: 50kb)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONTENT FRESHNESS

🔴 STALE (6+ months) - 4 pages
🟡 AGING (3-6 months) - 12 pages
🟢 FRESH (<3 months) - 231 pages

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LINK GRAPH

Orphaned Pages: 3
Deep Pages (5+ clicks): 7
Broken Links: 2

Most Linked:
1. /blog/ultimate-guide (47 links)
2. / (38 links)
3. /products (31 links)

[View Full Graph]
```

---

## Roadmap

### v0.1 (MVP)
- Content indexer
- Freshness tracker
- Performance budgets
- Link graph analysis
- Basic dashboard
- Sitemap generator
- robots.txt generator
- Meta tags manager

### v0.2
- Schema.org support
- Image analysis
- Heading validator
- RSS/Atom feeds
- Breadcrumbs

### v0.3
- Keyword extraction
- Content comparison
- Production metrics (opt-in)
- Dashboard improvements

### v1.0
- Content templates
- A/B test tracking
- Trend analysis
- Advanced visualizations
- Team features (maybe)

---

## Summary

**aris-content** turns content management into a joy by:

1. **Showing you problems** before they hurt SEO
2. **Making SEO declarative** at the handler level
3. **Tracking freshness** automatically via Git
4. **Enforcing budgets** so pages stay fast
5. **Finding weak spots** in your content structure
6. **Generating everything** (sitemap, robots, meta, schema)
7. **Zero production cost** - it's all dev-time or generated

**The DX is chef's kiss:** Write `sitemap`, `meta`, `schema` in your handler, and everything just works. No separate config files, no manual XML editing, no third-party tools.

**This doesn't exist anywhere else.** Not in Rails, not in Sinatra, not in JS frameworks, not in PHP. This is your competitive advantage as a solo dev managing multiple domains.

---

Ready to build? 🚀