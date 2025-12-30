# lib/aris/plugins/basic_auth.rb
require 'base64'

module Aris
  module Plugins
    class BasicAuth
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @realm = config[:realm] || 'Restricted Area'
        
        # Validate config
        if config[:validator]
          @validator = config[:validator]
        elsif config[:username] && config[:password]
          @validator = ->(u, p) { u == config[:username] && p == config[:password] }
        else
          raise ArgumentError, "BasicAuth requires either :validator or both :username and :password"
        end
      end
      
      def call(request, response)
        auth_header = request.headers['HTTP_AUTHORIZATION']
        
        unless auth_header && auth_header.start_with?('Basic ')
          return unauthorized_response(response, 'Missing or invalid Authorization header')
        end
        
        username, password = decode_credentials(auth_header)
        
        unless username && password
          return unauthorized_response(response, 'Invalid credentials format')
        end
        
        unless @validator.call(username, password)
          return unauthorized_response(response, 'Invalid username or password')
        end
        
        # Attach username to request for handlers
        request.instance_variable_set(:@current_user, username)
        nil # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def decode_credentials(auth_header)
        encoded = auth_header.sub('Basic ', '')
        decoded = Base64.decode64(encoded)
        decoded.split(':', 2)
      rescue => e
        [nil, nil]
      end
      
      def unauthorized_response(response, message)
        response.status = 401
        response.headers['content-type'] = 'text/plain'
        response.headers['WWW-Authenticate'] = %(Basic realm="#{@realm}")
        response.body = [message]
        response
      end
    end
  end
end