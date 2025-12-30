require 'securerandom'
module Aris
  module Plugins
    module CsrfUtility
      extend self
      def generate_token
        SecureRandom.urlsafe_base64(32)
      end
      def validate_token(expected, provided)
        expected && provided && expected == provided
      end
    end
    
    CSRF_THREAD_KEY = :aris_csrf_token
    FORM_METHODS = %w[POST PUT PATCH DELETE].freeze
        
    class CsrfTokenGenerator
      def self.call(request, response)
        if request.method == 'GET' || request.method == 'HEAD'
          token = CsrfUtility.generate_token
          Thread.current[CSRF_THREAD_KEY] = token
        end
        nil # Continue pipeline
      end
    end
    
    class CsrfProtection
      def self.call(request, response)
        return nil unless FORM_METHODS.include?(request.method)
        expected = Thread.current[CSRF_THREAD_KEY]
        provided = request.headers['HTTP_X_CSRF_TOKEN']
        unless CsrfUtility.validate_token(expected, provided)
          response.status = 403
          response.headers['content-type'] = 'text/plain'
          response.body = ['CSRF token validation failed']
          return response
        end
        
        nil
      end
    end

  end
end
Aris.register_plugin(:csrf, 
  generator: Aris::Plugins::CsrfTokenGenerator,
  protection: Aris::Plugins::CsrfProtection
)