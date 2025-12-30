# test/test_helper.rb
require 'benchmark'
require 'benchmark/ips'
require 'benchmark/memory'
require "minitest/autorun"
require "minitest/pride"
#require "minitest/reporters"
require "json"
require "stringio"

require_relative '../lib/aris/discovery'

#Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
class Minitest::Test
  def suppress_warnings
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original_stderr
  end
end
# Mock handler classes for testing
class UsersHandler; end
class UserHandler; end
class PostsHandler; end
class PostHandler; end
class UserPostHandler; end
class UsersIndexHandler; end
class UserUpdateHandler; def self.call(req, params); "Update User"; end; end
class UserDeleteHandler; def self.call(req, params); "Delete User"; end; end
class UsersCreateHandler; end
class HomeHandler; end
class SearchHandler; end
class NewUserHandler; end
class ShowUserHandler; end
class FileHandler; end
class WildcardHandler; end
class FilesHandler; end
class AssetsHandler; end
class ApiUsersHandler; end
class ExampleHomeHandler; end
class AdminHomeHandler; end
class HealthHandler; end
class ApiV1UsersHandler; end
class AdminUsersHandler; end
class PostsIndexHandler; end
class PostShowHandler; end
class CommentsIndexHandler; end
class CommentCreateHandler; end
class SubscribeFormHandler; end
class SubscribeSubmitHandler; end
class DashboardHandler; end
class AdminPostsIndexHandler; end
class AdminDashboardHandler; def self.call(req, params); "Dashboard"; end; end
class StatusHandler; def self.call(req, params); "Status OK"; end; end

class AdminPostCreateHandler; end
class AdminPostNewHandler; end
class AdminPostShowHandler; end
class AdminPostUpdateHandler; end
class AdminPostDestroyHandler; end
class AdminPostEditHandler; end
class AdminPostPublishHandler; end
class AdminTenantsIndexHandler; end
class AdminTenantCreateHandler; end
class AdminTenantShowHandler; end
class AdminTenantUpdateHandler; end
class ApiPostsIndexHandler; end
class ApiPostCreateHandler; end
class ApiPostShowHandler; end
class ApiPostsHandler; def self.call(req, params); "API Posts"; end; end
class ApiPostUpdateHandler; end
class ApiPostDestroyHandler; end
class WebhookPostPublishedHandler; end
class MetricsHandler; end
class GetHandler; end
class PostHandler; end
class PutHandler; end
class PatchHandler; end
class DeleteHandler; end
class UserPostsHandler; end
class ExampleUsersHandler; end
class ApiHandler; end
require_relative "../lib/aris"
require_relative "../lib/aris/adapters/mock/adapter"
# In test_helper.rb - add these test plugins
class TestPluginA
  def self.call(request, response); nil; end
end

class TestPluginB
  def self.call(request, response); nil; end
end

class TestPluginC
  def self.call(request, response); nil; end
end

class TestPluginPublic
  def self.call(request, response); nil; end
end

class TestPluginAdmin
  def self.call(request, response); nil; end
end


def response_handler(&block)
  ->(request, *args) {
    # If we get a response object as second arg, use it
    if args[0].is_a?(Aris::Adapters::Mock::Response) || args[0].is_a?(Aris::Adapters::Rack::Response)
      response = args[0]
      params = args[1] || {}
      instance_exec(request, response, params, &block)
    else
      # Otherwise, use traditional Rack array return
      params = args[0] || {}
      block.call(request, params)
    end
  }
end

# Register them
Aris.register_plugin(:plugin_a, plugin_class: TestPluginA)
Aris.register_plugin(:plugin_b, plugin_class: TestPluginB)
Aris.register_plugin(:plugin_c, plugin_class: TestPluginC)
Aris.register_plugin(:public, plugin_class: TestPluginPublic)
Aris.register_plugin(:admin_auth, plugin_class: TestPluginAdmin)
# Load the router implementation


#Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
