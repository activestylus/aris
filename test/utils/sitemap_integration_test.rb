# test/utils/sitemap_integration_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/utils/sitemap'
require 'fileutils'

class SitemapIntegrationTest < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "sitemap_test_#{Process.pid}_#{Time.now.to_i}")
    FileUtils.mkdir_p(@test_dir)
    Aris::Utils::Sitemap.reset!
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    Aris::Utils::Sitemap.reset!
    cleanup_namespaces
  end

  def test_autodiscovery_registers_sitemap
    create_route('example.com/about/get.rb', <<~RUBY)
      module Handler
        extend Aris::RouteHelpers
        
        sitemap priority: 0.8, changefreq: 'monthly'
        
        def self.call(request, params)
          "About page"
        end
      end
    RUBY

    Aris.discover_and_define(@test_dir)
    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/about</loc>'
    assert_includes xml, '<priority>0.8</priority>'
  end

  def test_hash_routes_with_sitemap
    Aris.routes({
      "example.com": {
        "/": {
          get: {
            to: ->(req, params) { "home" },
            sitemap: { priority: 1.0, changefreq: 'weekly' }
          }
        },
        "/about": {
          get: {
            to: ->(req, params) { "about" },
            sitemap: { priority: 0.8, changefreq: 'monthly' }
          }
        }
      }
    })

    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/</loc>'
    assert_includes xml, '<priority>1.0</priority>'
    assert_includes xml, '<loc>https://example.com/about</loc>'
    assert_includes xml, '<priority>0.8</priority>'
  end

  def test_routes_without_sitemap_excluded
    create_route('example.com/public/get.rb', <<~RUBY)
      module Handler
        extend Aris::RouteHelpers
        
        sitemap priority: 0.5, changefreq: 'monthly'
        
        def self.call(request, params)
          "public"
        end
      end
    RUBY

    create_route('example.com/admin/get.rb', <<~RUBY)
      module Handler
        extend Aris::RouteHelpers
        
        def self.call(request, params)
          "admin"
        end
      end
    RUBY

    Aris.discover_and_define(@test_dir)
    xml = Aris::Utils::Sitemap.generate(base_url: "https://example.com")
    
    assert_includes xml, '<loc>https://example.com/public</loc>'
    refute_includes xml, '<loc>https://example.com/admin</loc>'
  end

  private

  def create_route(path, content)
    file_path = File.join(@test_dir, path)
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, content)
  end

  def cleanup_namespaces
    %w[ExampleCom].each do |ns|
      Object.send(:remove_const, ns) if Object.const_defined?(ns)
    end
  rescue
  end
end