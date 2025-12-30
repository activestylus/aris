# lib/aris/plugins/compression.rb
require 'zlib'
require 'stringio'

module Aris
  module Plugins
    class Compression
      attr_reader :config
      
      # Compressible content types
      COMPRESSIBLE_TYPES = [
        'text/',
        'application/json',
        'application/javascript',
        'application/xml',
        'application/xhtml+xml'
      ].freeze
      
      def initialize(**config)
        @config = config
        @level = config[:level] || Zlib::DEFAULT_COMPRESSION
        @min_size = config[:min_size] || 1024  # Don't compress < 1KB
      end
      
      # Request hook - not used, but kept for compatibility
      def call(request, response)
        nil  # Do nothing on request phase
      end
      
      # Response hook - runs after handler
      def call_response(request, response)
        # Only compress if client accepts gzip
        accept_encoding = request.headers['HTTP_ACCEPT_ENCODING'] || ''
        return unless accept_encoding.include?('gzip')
        
        # Only compress if we have a body
        return if response.body.nil? || response.body.empty?
        
        # Get body as string
        body_string = response.body.join
        
        # Skip if too small
        return if body_string.bytesize < @min_size
        
        # Only compress compressible content types
        content_type = response.headers['content-type'] || ''
        return unless compressible?(content_type)
        
        # Compress the body
        compressed = compress_gzip(body_string)
        
        # Only use compression if it actually saves space
        if compressed.bytesize < body_string.bytesize
          response.body = [compressed]
          response.headers['Content-Encoding'] = 'gzip'
          response.headers['Vary'] = add_vary_header(response.headers['Vary'])
          response.headers.delete('Content-Length')  # Will be recalculated by server
        end
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def compressible?(content_type)
        COMPRESSIBLE_TYPES.any? { |type| content_type.start_with?(type) }
      end
      
      def compress_gzip(data)
        output = StringIO.new
        output.set_encoding('ASCII-8BIT')
        
        gz = Zlib::GzipWriter.new(output, @level)
        gz.write(data)
        gz.close
        
        output.string
      end
      
      def add_vary_header(existing_vary)
        if existing_vary.nil? || existing_vary.empty?
          'Accept-Encoding'
        elsif existing_vary.include?('Accept-Encoding')
          existing_vary
        else
          "#{existing_vary}, Accept-Encoding"
        end
      end
    end
  end
end

# Self-register
Aris.register_plugin(:compression, plugin_class: Aris::Plugins::Compression)