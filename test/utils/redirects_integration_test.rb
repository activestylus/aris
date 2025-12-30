# test/utils/redirects_integration_test.rb
require_relative '../test_helper'
require_relative '../../lib/aris/utils/redirects'
require 'fileutils'

class RedirectsIntegrationTest < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "redirects_test_#{Process.pid}_#{Time.now.to_i}")
    FileUtils.mkdir_p(@test_dir)
    Aris::Utils::Redirects.reset!
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
    Aris::Utils::Redirects.reset!
    cleanup_namespaces
  end

  def test_autodiscovery_registers_redirects
    create_route('example.com/new-blog/get.rb', <<~RUBY)
      module Handler
        extend Aris::RouteHelpers
        
        redirects_from '/old-blog', '/blog-archive'
        
        def self.call(request, params)
          "new blog"
        end
      end
    RUBY

    Aris.discover_and_define(@test_dir)

    assert_equal '/new-blog', Aris::Utils::Redirects.find('/old-blog')[:to]
    assert_equal '/new-blog', Aris::Utils::Redirects.find('/blog-archive')[:to]
  end

  def test_hash_routes_with_redirects
    Aris.routes({
      "example.com": {
        "/new-path": {
          get: {
            to: ->(req, params) { "content" },
            redirects_from: ['/old-path', '/legacy-path']
          }
        }
      }
    })

    assert_equal '/new-path', Aris::Utils::Redirects.find('/old-path')[:to]
    assert_equal '/new-path', Aris::Utils::Redirects.find('/legacy-path')[:to]
  end

  def test_custom_redirect_status
    create_route('example.com/temp/get.rb', <<~RUBY)
      module Handler
        extend Aris::RouteHelpers
        
        redirects_from '/old-temp', status: 302
        
        def self.call(request, params)
          "temp page"
        end
      end
    RUBY

    Aris.discover_and_define(@test_dir)

    redirect = Aris::Utils::Redirects.find('/old-temp')
    assert_equal 302, redirect[:status]
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