require_relative 'test_helper'
require 'fileutils'

class DiscoveryTest < Minitest::Test
  def setup
    @test_dir = File.join(Dir.tmpdir, "aris_test_#{Process.pid}_#{Time.now.to_i}")
    FileUtils.mkdir_p(@test_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if @test_dir && Dir.exist?(@test_dir)
    cleanup_namespaces
  end

  def test_discovers_simple_route
    create_route('example.com/index/get.rb', 'class Handler; def self.call(req, params); "home"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert routes["example.com"]["/"][:get][:to].call(nil, {}) == "home"
  end

  def test_discovers_multiple_http_methods
    create_route('example.com/users/get.rb', 'class Handler; def self.call(req, params); "list"; end; end')
    create_route('example.com/users/post.rb', 'class Handler; def self.call(req, params); "create"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "list", routes["example.com"]["/users"][:get][:to].call(nil, {})
    assert_equal "create", routes["example.com"]["/users"][:post][:to].call(nil, {})
  end

  def test_discovers_parameterized_routes
    create_route('example.com/users/_id/get.rb', 'class Handler; def self.call(req, params); "user #{params[:id]}"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "user 123", routes["example.com"]["/users"][":id"][:get][:to].call(nil, { id: "123" })
  end

  def test_discovers_nested_params
    create_route('example.com/users/_uid/posts/_pid/get.rb', 'class Handler; def self.call(req, params); "#{params[:uid]}/#{params[:pid]}"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "42/99", routes["example.com"]["/users"][":uid"]["/posts"][":pid"][:get][:to].call(nil, { uid: "42", pid: "99" })
  end

  def test_discovers_wildcard_domain
    create_route('_/health/get.rb', 'class Handler; def self.call(req, params); "ok"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "ok", routes["*"]["/health"][:get][:to].call(nil, {})
  end

  def test_discovers_multiple_domains
    create_route('example.com/index/get.rb', 'class Handler; def self.call(req, params); "main"; end; end')
    create_route('api.example.com/status/get.rb', 'class Handler; def self.call(req, params); "api"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "main", routes["example.com"]["/"][:get][:to].call(nil, {})
    assert_equal "api", routes["api.example.com"]["/status"][:get][:to].call(nil, {})
  end

  def test_deeply_nested_paths
    create_route('example.com/api/v1/admin/users/get.rb', 'class Handler; def self.call(req, params); "admin"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal "admin", routes["example.com"]["/api"]["/v1"]["/admin"]["/users"][:get][:to].call(nil, {})
  end

  def test_handler_namespacing_prevents_conflicts
    create_route('example.com/users/get.rb', 'class Handler; def self.call(req, params); "users"; end; end')
    create_route('example.com/posts/get.rb', 'class Handler; def self.call(req, params); "posts"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    users = routes["example.com"]["/users"][:get][:to]
    posts = routes["example.com"]["/posts"][:get][:to]

    refute_equal users, posts
    assert_equal "users", users.call(nil, {})
    assert_equal "posts", posts.call(nil, {})
  end

  def test_all_http_methods
    %w[get post put patch delete options].each do |method|
      create_route("example.com/test/#{method}.rb", "class Handler; def self.call(req, params); '#{method}'; end; end")
    end
    routes = Aris::Discovery.discover(@test_dir)

    %i[get post put patch delete options].each do |method|
      assert_equal method.to_s, routes["example.com"]["/test"][method][:to].call(nil, {})
    end
  end

  def test_ignores_invalid_http_methods
    create_route('example.com/test/invalid.rb', 'class Handler; def self.call(req, params); "bad"; end; end')
    create_route('example.com/test/get.rb', 'class Handler; def self.call(req, params); "good"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    refute routes.dig("example.com", "/test", :invalid)
    assert routes["example.com"]["/test"][:get]
  end

def test_handles_missing_handler_constant
  create_route('example.com/broken/get.rb', 'class SomethingElse; end')
  
  # Capture and discard warnings
  original_stderr = $stderr
  $stderr = StringIO.new
  
  routes = Aris::Discovery.discover(@test_dir)
  
  $stderr = original_stderr
  
  refute routes.dig("example.com", "/broken", :get)
end

def test_handles_syntax_errors
  create_route('example.com/broken/get.rb', 'class Handler; def call(')
  
  # Capture and discard warnings
  original_stderr = $stderr
  $stderr = StringIO.new
  
  routes = Aris::Discovery.discover(@test_dir)
  
  $stderr = original_stderr
  
  refute routes.dig("example.com", "/broken", :get)
end

def test_validates_handler_responds_to_call
  create_route('example.com/invalid/get.rb', 'class Handler; end')
  
  suppress_warnings do
    routes = Aris::Discovery.discover(@test_dir)
    refute routes.dig("example.com", "/invalid", :get)
  end
end

  def test_index_represents_root
    create_route('example.com/users/index/get.rb', 'class Handler; def self.call(req, params); "root"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert routes["example.com"]["/users"][:get]
    refute routes.dig("example.com", "/users", "/index")
  end

  def test_empty_directory
    routes = Aris::Discovery.discover(@test_dir)
    assert_empty routes
  end

  def test_case_insensitive_http_methods
    create_route('example.com/test/GET.rb', 'class Handler; def self.call(req, params); "ok"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert routes["example.com"]["/test"][:get]
  end

  def test_ignores_non_ruby_files
    create_route('example.com/test/get.rb', 'class Handler; def self.call(req, params); "ruby"; end; end')
    File.write(File.join(@test_dir, 'example.com/test/readme.txt'), 'ignore')
    routes = Aris::Discovery.discover(@test_dir)

    assert_equal 1, routes["example.com"]["/test"].keys.size
  end

  def test_preserves_return_values
    create_route('example.com/hash/get.rb', 'class Handler; def self.call(req, params); {a: 1}; end; end')
    create_route('example.com/string/get.rb', 'class Handler; def self.call(req, params); "text"; end; end')
    routes = Aris::Discovery.discover(@test_dir)

    assert_kind_of Hash, routes["example.com"]["/hash"][:get][:to].call(nil, {})
    assert_equal "text", routes["example.com"]["/string"][:get][:to].call(nil, {})
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