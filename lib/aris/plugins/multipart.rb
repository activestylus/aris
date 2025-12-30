# lib/aris/plugins/multipart.rb
require 'tempfile'
require 'securerandom'

module Aris
  module Plugins
    class Multipart
      attr_reader :config
      
      PARSEABLE_METHODS = %w[POST PUT PATCH].freeze
      
      def initialize(**config)
        @config = config
        @max_file_size = config[:max_file_size] || 10_485_760  # 10MB default
        @max_files = config[:max_files] || 10
        @allowed_extensions = config[:allowed_extensions]  # nil = all allowed
      end
      
      def call(request, response)
        return nil unless PARSEABLE_METHODS.include?(request.method)
        
        content_type = request.env['CONTENT_TYPE']
        return nil unless content_type&.include?('multipart/form-data')
        
        # Extract boundary from content type
        boundary = extract_boundary(content_type)
        unless boundary
          response.status = 400
          response.headers['content-type'] = 'text/plain'
          response.body = ['Missing boundary in multipart request']
          return response
        end
        
        raw_body = request.body
        return nil if raw_body.nil? || raw_body.empty?
        
        begin
          # Parse multipart data
          parts = parse_multipart(raw_body, boundary)
          
          # Validate file count
          files = parts.select { |p| p[:filename] }
          if files.size > @max_files
            response.status = 413
            response.headers['content-type'] = 'text/plain'
            response.body = ["Too many files (max #{@max_files})"]
            return response
          end
          
          # Validate file sizes and extensions
          files.each do |file|
            if file[:data].bytesize > @max_file_size
              response.status = 413
              response.headers['content-type'] = 'text/plain'
              response.body = ["File '#{file[:filename]}' exceeds maximum size (#{@max_file_size} bytes)"]
              return response
            end
            
            if @allowed_extensions
              ext = File.extname(file[:filename]).downcase
              unless @allowed_extensions.include?(ext)
                response.status = 400
                response.headers['content-type'] = 'text/plain'
                response.body = ["File type '#{ext}' not allowed"]
                return response
              end
            end
          end
          
          # Attach parsed data to request
          request.instance_variable_set(:@multipart_data, parts)
          
        rescue => e
          response.status = 400
          response.headers['content-type'] = 'text/plain'
          response.body = ['Invalid multipart data']
          return response
        end
        
        nil  # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def extract_boundary(content_type)
        match = content_type.match(/boundary=(?:"([^"]+)"|([^;]+))/)
        match ? (match[1] || match[2]) : nil
      end
      
      def parse_multipart(body, boundary)
        parts = []
        delimiter = "--#{boundary}"
        
        # Split by boundary
        sections = body.split(delimiter)
        
        # Skip first (empty) and last (closing) sections
        sections[1..-2]&.each do |section|
          next if section.strip.empty?
          
          # Split headers from content
          header_end = section.index("\r\n\r\n") || section.index("\n\n")
          next unless header_end
          
          headers_raw = section[0...header_end]
          content = section[(header_end + 4)..-1]
          
          # Remove trailing CRLF
          content = content.chomp("\r\n").chomp("\n")
          
          # Parse Content-Disposition header
          disposition = headers_raw.match(/Content-Disposition:\s*(.+?)(?:\r?\n|$)/i)
          next unless disposition
          
          disposition_value = disposition[1]
          
          # Extract field name
          name_match = disposition_value.match(/name="([^"]+)"/)
          name = name_match ? name_match[1] : nil
          next unless name
          
          # Extract filename if present (indicates file upload)
          filename_match = disposition_value.match(/filename="([^"]+)"/)
          filename = filename_match ? filename_match[1] : nil
          
          # Extract content type if present
          content_type_match = headers_raw.match(/content-type:\s*(.+?)(?:\r?\n|$)/i)
          content_type = content_type_match ? content_type_match[1].strip : nil
          
          if filename
            # File upload
            parts << {
              name: name,
              filename: filename,
              content_type: content_type || 'application/octet-stream',
              data: content,
              type: :file
            }
          else
            # Regular form field
            parts << {
              name: name,
              data: content,
              type: :field
            }
          end
        end
        
        parts
      end
    end
  end
end

# Self-register
Aris.register_plugin(:multipart, plugin_class: Aris::Plugins::Multipart)