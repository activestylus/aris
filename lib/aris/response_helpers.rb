# lib/aris/response_helpers.rb
require 'json'

module Aris
  module ResponseHelpers
    # JSON response
    def json(data, status: 200)
      self.status = status
      self.headers['content-type'] = 'application/json'
      self.body = [data.to_json]
      self
    end
    
    # HTML response
    def html(content, status: 200)
      self.status = status
      self.headers['content-type'] = 'text/html; charset=utf-8'
      self.body = [content.to_s]
      self
    end


    def negotiate(format_preference, status: 200, &block)
      format_to_use = case format_preference.to_s
      when 'json', 'application/json' then :json
      when 'xml', 'application/xml' then :xml
      when 'html', 'text/html' then :html
      else :json
      end
      
      content = block.call(format_to_use) if block_given?
      
      case format_to_use
      when :json
        if content.is_a?(String) && content.start_with?('{', '[')
          self.status = status
          self.headers['content-type'] = 'application/json'
          self.body = [content]
        else
          json(content || {}, status: status)
        end
      when :xml
        xml(content || '', status: status)
      when :html
        html(content || '', status: status)
      end
      
      self
    end

    # Plain text response
    def text(content, status: 200)
      self.status = status
      self.headers['content-type'] = 'text/plain; charset=utf-8'
      self.body = [content.to_s]
      self
    end
    
    # Redirect to URL
    def redirect(url, status: 302)
      self.status = status
      self.headers['location'] = url
      self.headers['content-type'] = 'text/plain; charset=utf-8'
      self.body = ["Redirecting to #{url}"]
      self
    end
    
    # Redirect to named route
    def redirect_to(route_name, status: 302, **params)
      # Get domain from Thread context (set by adapter)
      domain = Thread.current[:aris_current_domain]
      path = Aris.path(domain, route_name, **params)
      redirect(path, status: status)
    end
    
    # No content response
    def no_content
      self.status = 204
      self.headers.delete('content-type')
      self.body = []
      self
    end
    
    # XML response
    def xml(data, status: 200)
      self.status = status
      self.headers['content-type'] = 'application/xml; charset=utf-8'
      self.body = [data.to_s]
      self
    end
    
    # Send file
    def send_file(file_path, filename: nil, type: nil, disposition: 'attachment')
      unless File.exist?(file_path)
        raise ArgumentError, "File not found: #{file_path}"
      end
      
      self.status = 200
      
      # Determine content type
      content_type = type || detect_content_type(file_path)
      self.headers['content-type'] = content_type
      
      # Set filename
      download_filename = filename || File.basename(file_path)
      self.headers['content-disposition'] = "#{disposition}; filename=\"#{download_filename}\""
      
      # Set content length
      self.headers['content-length'] = File.size(file_path).to_s
      
      # Read file
      self.body = [File.read(file_path)]
      
      self
    end
    
    private
    
    def detect_content_type(file_path)
      # Handle Tempfile paths that may have random extensions
      ext = File.extname(file_path).downcase
      ext = ext.split('.').last if ext.include?('.')
      ext = ".#{ext}" unless ext.start_with?('.')
      
      MIME_TYPES[ext] || 'application/octet-stream'
    end
    
    MIME_TYPES = {
      '.html' => 'text/html',
      '.htm' => 'text/html',
      '.txt' => 'text/plain',
      '.css' => 'text/css',
      '.js' => 'application/javascript',
      '.json' => 'application/json',
      '.xml' => 'application/xml',
      '.pdf' => 'application/pdf',
      '.zip' => 'application/zip',
      '.tar' => 'application/x-tar',
      '.gz' => 'application/gzip',
      '.jpg' => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.svg' => 'image/svg+xml',
      '.webp' => 'image/webp',
      '.ico' => 'image/x-icon',
      '.mp3' => 'audio/mpeg',
      '.mp4' => 'video/mp4',
      '.webm' => 'video/webm',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf'
    }.freeze
  end
end