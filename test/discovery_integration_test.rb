require_relative 'test_helper'
require 'fileutils'

class DiscoveryIntegrationTest < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "aris_int_test_#{Process.pid}_#{Time.now.to_i}")
    FileUtils.mkdir_p(@test_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    cleanup_namespaces
  end

  def test_discover_and_define
    create_route('example.com/test/get.rb', 'class Handler; def self.call(req, params); "ok"; end; end')
    
    Aris.discover_and_define(@test_dir)
    result = Aris::Router.match(domain: "example.com", method: :get, path: "/test")

    assert result
    assert_equal "ok", result[:handler].call(nil, result[:params])
  end

  def test_parameterized_routes_with_matching
    create_route('example.com/users/_id/get.rb', 'class Handler; def self.call(req, params); "user #{params[:id]}"; end; end')
    
    Aris.discover_and_define(@test_dir)
    result = Aris::Router.match(domain: "example.com", method: :get, path: "/users/123")

    assert result
    assert_equal "123", result[:params][:id]
    assert_equal "user 123", result[:handler].call(nil, result[:params])
  end

  def test_wildcard_domain_matching
    create_route('_/health/get.rb', 'class Handler; def self.call(req, params); "healthy"; end; end')
    
    Aris.discover_and_define(@test_dir)
    result = Aris::Router.match(domain: "unknown.com", method: :get, path: "/health")

    assert result
    assert_equal "healthy", result[:handler].call(nil, result[:params])
  end

  def test_multiple_methods_same_path
    create_route('example.com/users/get.rb', 'class Handler; def self.call(req, params); "list"; end; end')
    create_route('example.com/users/post.rb', 'class Handler; def self.call(req, params); "create"; end; end')
    
    Aris.discover_and_define(@test_dir)
    
    get_result = Aris::Router.match(domain: "example.com", method: :get, path: "/users")
    post_result = Aris::Router.match(domain: "example.com", method: :post, path: "/users")

    assert_equal "list", get_result[:handler].call(nil, get_result[:params])
    assert_equal "create", post_result[:handler].call(nil, post_result[:params])
  end

  def test_route_structure_matches_aris
    create_route('example.com/users/_id/get.rb', 'class Handler; def self.call(req, params); "ok"; end; end')
    
    discovered = Aris::Discovery.discover(@test_dir)

    assert_kind_of Hash, discovered
    assert discovered["example.com"]["/users"][":id"][:get].key?(:to)
    assert_respond_to discovered["example.com"]["/users"][":id"][:get][:to], :call
  end

  private

  def create_route(path, content)
    file_path = File.join(@test_dir, path)
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, content)
  end

  def cleanup_namespaces
    %w[ExampleCom ApiExampleCom Wildcard].each do |ns|
      Object.send(:remove_const, ns) if Object.const_defined?(ns)
    end
  rescue
  end
end