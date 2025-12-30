# lib/aris/adapters/mock/request.rb
module Aris
  module Adapters
    module Mock
      class Request
        attr_reader :raw_request, :cookies  # Add cookies
        attr_accessor :json_body
        
        def initialize(method:, path:, domain:, headers: {}, body: '', query: '', cookies: {})  # Add cookies parameter
          @raw_request = {
            method: method.to_s.upcase,
            path: path,
            domain: domain,
            headers: headers,
            body: body,
            query: query
          }
          @cookies = cookies || {}  # Initialize cookies
        end
        
        # Add env method for plugin compatibility
        def env
          @raw_request[:headers]
        end
        
        def host
          @raw_request[:domain]
        end
        
        alias_method :domain, :host

        def request_method
          @raw_request[:method]
        end
        
        def method
          @raw_request[:method]
        end

        def path_info
          @raw_request[:path]
        end
        
        alias_method :path, :path_info

        def query
          @raw_request[:query]
        end

        def headers
          @raw_request[:headers]
        end

        def body
          @raw_request[:body]
        end

        def params
          # Simple query string parser (no external dependencies)
          return @params if @params
          @params = {}
          query.split('&').each do |pair|
            key, value = pair.split('=')
            @params[key] = value if key
          end
          @params
        end
        
        def [](key)
          case key
          when :method then method
          when :domain then domain
          when :path then path
          when :host then host
          else @raw_request[key]
          end
        end
      end
    end
  end
end