# lib/aris/adapters/rack/request.rb
module Aris
  module Adapters
    module Rack
      class Request
        attr_reader :env
        attr_accessor :json_body
        
        def initialize(env)
          @env = env
        end
        
        # Add cookies method to match Mock adapter interface
        def cookies
          @env['rack.request.cookie_hash'] || {}
        end
        
        def host
          @env['HTTP_HOST'] || @env['SERVER_NAME']
        end
        
        alias_method :domain, :host

        def request_method
          @env['REQUEST_METHOD']
        end
        
        def method
          @env['REQUEST_METHOD']
        end

        def path_info
          @env['PATH_INFO']
        end
        
        alias_method :path, :path_info

        def query
          @env['QUERY_STRING']
        end

        def headers
          @env.select { |k, v| k.start_with?('HTTP_') }
        end

        def body
          @env['rack.input']&.read
        end

        def params
          @params ||= ::Rack::Utils.parse_nested_query(@env['QUERY_STRING'] || '')
        end
        
        def [](key)
          case key
          when :method then method
          when :domain then domain
          when :path then path
          when :host then host
          else @env[key.to_s]
          end
        end
      end
    end
  end
end