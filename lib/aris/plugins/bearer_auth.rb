# lib/aris/plugins/bearer_auth.rb

module Aris
  module Plugins
    class BearerAuth
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @realm = config[:realm] || 'API'
        
        # Validate config
        if config[:validator]
          @validator = config[:validator]
        elsif config[:token]
          @validator = ->(t) { t == config[:token] }
        else
          raise ArgumentError, "BearerAuth requires either :validator or :token"
        end
      end
      
      def call(request, response)
        auth_header = request.headers['HTTP_AUTHORIZATION']
        
        unless auth_header && auth_header.start_with?('Bearer ')
          return unauthorized_response(response, 'Missing or invalid Authorization header')
        end
        
        token = extract_token(auth_header)
        
        unless token && !token.empty?
          return unauthorized_response(response, 'Invalid token format')
        end
        
        unless @validator.call(token)
          return unauthorized_response(response, 'Invalid or expired token')
        end
        
        # Attach token to request for handlers
        request.instance_variable_set(:@bearer_token, token)
        nil # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def extract_token(auth_header)
        auth_header.sub('Bearer ', '').strip
      end
      
      def unauthorized_response(response, message)
        response.status = 401
        response.headers['content-type'] = 'application/json'
        response.headers['WWW-Authenticate'] = %(Bearer realm="#{@realm}")
        response.body = [JSON.generate({ error: 'Unauthorized', message: message })]
        response
      end
    end
  end
end
Aris.register_plugin(:bearer_auth, plugin_class: Aris::Plugins::BearerAuth)