# security_headers.rb

module Aris
  module Plugins
    class SecurityHeaders
      attr_reader :config
      
      # Default secure headers
      DEFAULTS = {
        'X-Frame-Options' => 'SAMEORIGIN',
        'X-content-type-Options' => 'nosniff',
        'X-XSS-Protection' => '0',  # Modern browsers ignore this, disabled preferred
        'Referrer-Policy' => 'strict-origin-when-cross-origin'
      }.freeze
      
      def initialize(**config)
        @config = config
        @headers = build_headers(config)
      end
      
      def call(request, response)
        # Set all configured headers
        @headers.each do |key, value|
          response.headers[key] = value
        end
        
        nil  # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
def build_headers(config)
  headers = {}
  
  # Start with defaults unless disabled
  unless config[:defaults] == false
    headers.merge!(DEFAULTS)
  end
  
  # X-Frame-Options
  if config.key?(:x_frame_options)
    if config[:x_frame_options]
      headers['X-Frame-Options'] = config[:x_frame_options]
    else
      headers.delete('X-Frame-Options')  # ✅ Explicitly remove when nil
    end
  end
  
  # X-content-type-Options
  if config.key?(:x_content_type_options)
    if config[:x_content_type_options]
      headers['X-content-type-Options'] = config[:x_content_type_options]
    else
      headers.delete('X-content-type-Options')  # ✅ Explicitly remove when nil
    end
  end
  
  # Referrer-Policy
  if config.key?(:referrer_policy)
    if config[:referrer_policy]
      headers['Referrer-Policy'] = config[:referrer_policy]
    else
      headers.delete('Referrer-Policy')  # ✅ Explicitly remove when nil
    end
  end
  
  # HSTS (same as before)
  if config[:hsts]
    hsts_value = if config[:hsts].is_a?(Hash)
      max_age = config[:hsts][:max_age] || 31536000
      directives = ["max-age=#{max_age}"]
      directives << 'includeSubDomains' if config[:hsts][:include_subdomains]
      directives << 'preload' if config[:hsts][:preload]
      directives.join('; ')
    else
      'max-age=31536000; includeSubDomains'
    end
    headers['Strict-Transport-Security'] = hsts_value
  end
  
  # CSP (same as before)
  if config[:csp]
    headers['Content-Security-Policy'] = config[:csp]
  end
  
  # Permissions-Policy (same as before)
  if config[:permissions_policy]
    headers['Permissions-Policy'] = config[:permissions_policy]
  end
  
  headers
end
    end
  end
end