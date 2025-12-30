# test/utils/sitemap_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/utils/sitemap'

class SitemapUtilTest < Minitest::Test
  def setup
    Aris::Utils::Sitemap.reset!
  end

  def teardown
    Aris::Utils::Sitemap.reset!
  end

  def test_static_route_registration
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/about",
      method: :get,
      metadata: { priority: 0.8, changefreq: 'monthly' }
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/about</loc>'
    assert_includes xml, '<priority>0.8</priority>'
    assert_includes xml, '<changefreq>monthly</changefreq>'
  end

  def test_multiple_routes
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/",
      method: :get,
      metadata: { priority: 1.0, changefreq: 'weekly' }
    )
    
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/about",
      method: :get,
      metadata: { priority: 0.8, changefreq: 'monthly' }
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/</loc>'
    assert_includes xml, '<loc>https://example.com/about</loc>'
  end

  def test_routes_sorted_by_priority
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/low",
      method: :get,
      metadata: { priority: 0.3, changefreq: 'yearly' }
    )
    
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/high",
      method: :get,
      metadata: { priority: 1.0, changefreq: 'daily' }
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    high_index = xml.index('/high')
    low_index = xml.index('/low')
    
    assert high_index < low_index
  end

  def test_dynamic_routes
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/posts/:slug",
      method: :get,
      metadata: {
        priority: 0.7,
        changefreq: 'weekly',
        dynamic: -> {
          [
            { path: "/posts/hello-world", lastmod: "2024-01-15", priority: 0.7, changefreq: 'weekly' },
            { path: "/posts/ruby-tips", lastmod: "2024-02-01", priority: 0.7, changefreq: 'weekly' }
          ]
        }
      }
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/posts/hello-world</loc>'
    assert_includes xml, '<loc>https://example.com/posts/ruby-tips</loc>'
    assert_includes xml, '<lastmod>2024-01-15</lastmod>'
  end

  def test_excludes_routes_without_metadata
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/public",
      method: :get,
      metadata: { priority: 0.5, changefreq: 'monthly' }
    )
    
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/admin",
      method: :get,
      metadata: nil
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/public</loc>'
    refute_includes xml, '<loc>https://example.com/admin</loc>'
  end

  def test_domain_filtering
    Aris::Utils::Sitemap.register(
      domain: "example.com",
      path: "/",
      method: :get,
      metadata: { priority: 1.0, changefreq: 'weekly' }
    )
    
    Aris::Utils::Sitemap.register(
      domain: "api.example.com",
      path: "/",
      method: :get,
      metadata: { priority: 0.8, changefreq: 'daily' }
    )

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com", domain: "example.com")
    
    assert_includes xml, '<loc>https://example.com/</loc>'
    refute_includes xml, 'api.example.com'
  end

  def test_empty_sitemap
    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<urlset'
    assert_includes xml, '</urlset>'
    refute_includes xml, '<url>'
  end
end