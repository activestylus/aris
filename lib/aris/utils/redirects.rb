# lib/aris/utils/redirects.rb
module Aris
  module Utils
    module Redirects
      class << self
        attr_reader :redirects
        
        def reset!
          @redirects = {}
        end
        
        def register(from_paths:, to_path:, status: 301)
          @redirects ||= {}
          Array(from_paths).each do |from_path|
            @redirects[from_path] = { to: to_path, status: status }
          end
        end
        
        def find(path)
          @redirects&.[](path)
        end
        
        def all
          @redirects || {}
        end
      end
      
      reset!
    end
  end
end

# Extend RouteHelpers
module Aris
	module RouteHelpers
  def redirects_from(*paths, status: 301)
    @_redirect_paths = { paths: paths, status: status }
  end
  
  def redirect_metadata
    @_redirect_paths
  end
  end
end