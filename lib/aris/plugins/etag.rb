# lib/aris/plugins/etag.rb
require 'digest'

module Aris
  module Plugins
    class ETag
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @cache_control = config[:cache_control] || 'max-age=0, private, must-revalidate'
        @strong = config[:strong].nil? ? true : config[:strong]
      end
      
      # Request hook - check If-None-Match
      def call(request, response)
        if_none_match = request.headers['HTTP_IF_NONE_MATCH']
        
        # Store for later comparison in response phase
        request.instance_variable_set(:@if_none_match, if_none_match)
        
        nil  # Continue to handler
      end
      
      # Response hook - generate ETag and check match
      def call_response(request, response)
        # Only generate ETags for successful GET/HEAD requests
        return unless %w[GET HEAD].include?(request.method)
        return unless response.status == 200
        
        # Skip if response already has ETag
        return if response.headers['ETag']
        
        # Generate ETag from body
        body_string = response.body.join
        etag = generate_etag(body_string)
        
        # Set ETag header
        response.headers['ETag'] = etag
        
        # Set Cache-Control if not already set
        unless response.headers['Cache-Control']
          response.headers['Cache-Control'] = @cache_control
        end
        
        # Check if client's ETag matches
        if_none_match = request.instance_variable_get(:@if_none_match)
        if if_none_match && etag_match?(if_none_match, etag)
          # Return 304 Not Modified
          response.status = 304
          response.body = []
        end
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def generate_etag(body)
        hash = Digest::MD5.hexdigest(body)
        if @strong
          %("#{hash}")  # Strong ETag with quotes
        else
          %(W/"#{hash}")  # Weak ETag
        end
      end
      
      def etag_match?(if_none_match, etag)
        # Handle multiple ETags in If-None-Match
        client_etags = if_none_match.split(',').map(&:strip)
        
        # Check if any client ETag matches
        client_etags.any? do |client_etag|
          # Strip W/ prefix for weak comparison
          normalize_etag(client_etag) == normalize_etag(etag)
        end
      end
      
      def normalize_etag(etag)
        # Remove W/ prefix and quotes for comparison
        etag.sub(/^W\//, '').gsub('"', '')
      end
    end
  end
end

# Self-register
Aris.register_plugin(:etag, plugin_class: Aris::Plugins::ETag)