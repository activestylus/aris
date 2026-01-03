module Aris
  module Config
    class << self
      attr_accessor :trailing_slash, :trailing_slash_status,:secret_key_base, :cookie_options, :serve_static
      DEFAULT_MIME_TYPES = {
        '.html' => 'text/html',
        '.css' => 'text/css',
        '.js' => 'application/javascript',
        '.json' => 'application/json',
        '.jpg' => 'image/jpeg',
        '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.gif' => 'image/gif',
        '.svg' => 'image/svg+xml',
        '.webp' => 'image/webp',
        '.ico' => 'image/x-icon',
        '.woff' => 'font/woff',
        '.woff2' => 'font/woff2',
        '.ttf' => 'font/ttf',
        '.pdf' => 'application/pdf',
        '.xml' => 'application/xml',
        '.txt' => 'text/plain',
        '.mp3' => 'audio/mpeg',
        '.wav' => 'audio/wav',
        '.ogg' => 'audio/ogg',
        '.flac' => 'audio/flac',
        '.m4a' => 'audio/mp4'
      }.freeze
      def mime_types
        @mime_types ||= DEFAULT_MIME_TYPES.dup
      end
      
      def mime_types=(custom_types)
        @mime_types = DEFAULT_MIME_TYPES.merge(custom_types)
      end

      def reset!
        @trailing_slash = :strict
        @serve_static = false
        @trailing_slash_status = 301
        @secret_key_base = nil
        @cookie_options = {
          httponly: true,
          secure: false, # Default to false for development
          same_site: :lax,
          path: '/'
        }
      end
    end
    
    reset!
  end
end