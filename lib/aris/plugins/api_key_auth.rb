# lib/aris/plugins/api_key_auth.rb

module Aris
  module Plugins
    class ApiKeyAuth
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @header = config[:header] || 'X-API-Key'
        @realm = config[:realm] || 'API'
        
        # Validate config
        if config[:validator]
          @validator = config[:validator]
        elsif config[:key]
          @validator = ->(k) { k == config[:key] }
        elsif config[:keys]
          valid_keys = Array(config[:keys])
          @validator = ->(k) { valid_keys.include?(k) }
        else
          raise ArgumentError, "ApiKeyAuth requires :validator, :key, or :keys"
        end
      end
      
      def call(request, response)
        # Extract key from header
        header_key = "HTTP_#{@header.upcase.gsub('-', '_')}"
        api_key = request.headers[header_key]
        
        unless api_key && !api_key.empty?
          return unauthorized_response(response, 'Missing API key')
        end
        
        unless @validator.call(api_key)
          return unauthorized_response(response, 'Invalid API key')
        end
        
        # Attach key to request for handlers
        request.instance_variable_set(:@api_key, api_key)
        nil # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def unauthorized_response(response, message)
        response.status = 401
        response.headers['content-type'] = 'application/json'
        response.headers['WWW-Authenticate'] = %(ApiKey realm="#{@realm}")
        response.body = [JSON.generate({ error: 'Unauthorized', message: message })]
        response
      end
    end
  end
end

Aris.register_plugin(:api_key, plugin_class: Aris::Plugins::ApiKeyAuth)