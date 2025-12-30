# lib/aris/plugins/cors.rb

module Aris
  module Plugins
    class Cors
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @origins = normalize_origins(config[:origins] || '*')
        @methods = config[:methods] || ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']
        @headers = config[:headers] || ['content-type', 'Authorization']
        @credentials = config[:credentials] || false
        @max_age = config[:max_age] || 86400  # 24 hours
        @expose_headers = config[:expose_headers] || []
      end
      
      def call(request, response)
        origin = request.headers['HTTP_ORIGIN']
        
        # No Origin header = not a CORS request
        return nil unless origin
        
        # Check if origin is allowed
        unless origin_allowed?(origin)
          return nil  # Don't set CORS headers for disallowed origins
        end
        
        # Set CORS headers
        response.headers['Access-Control-Allow-Origin'] = allowed_origin_header(origin)
        response.headers['Access-Control-Allow-Methods'] = @methods.join(', ')
        response.headers['Access-Control-Allow-Headers'] = @headers.join(', ')
        response.headers['Access-Control-Max-Age'] = @max_age.to_s
        
        if @credentials
          response.headers['Access-Control-Allow-Credentials'] = 'true'
        end
        
        if @expose_headers.any?
          response.headers['Access-Control-Expose-Headers'] = @expose_headers.join(', ')
        end
        
        # Handle preflight OPTIONS request
        if request.method == 'OPTIONS'
          response.status = 204
          response.body = []
          return response  # Halt - don't proceed to handler
        end
        
        nil  # Continue for actual requests
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def normalize_origins(origins)
        return '*' if origins == '*'
        Array(origins)
      end
      
      def origin_allowed?(origin)
        return true if @origins == '*'
        @origins.include?(origin)
      end
      
      def allowed_origin_header(origin)
        # If credentials true, must echo specific origin (can't use *)
        if @credentials && @origins == '*'
          origin
        elsif @origins == '*'
          '*'
        else
          origin
        end
      end
    end
  end
end