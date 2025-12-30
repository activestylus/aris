# lib/aris/route_helpers.rb
module Aris
  module RouteHelpers
    # Declare localized paths (for file discovery)
    # @example
    #   localized es: 'acerca', en: 'about'
    def localized(**paths)
      @_localized_paths = paths
    end
    
    def localized_paths
      @_localized_paths || {}
    end
    
    # Load localized data - SUPPORTS MULTIPLE FORMATS (.rb, .json, .yml)
    # @param locale [Symbol] The locale to load data for (:es, :en, etc.)
    # @return [Hash] The parsed data for the locale
    # @raise [Aris::Router::LocaleError] If no data file found for locale
    def load_localized_data(locale)
      base_path = File.dirname(caller_locations.first.path)
      
      # Try multiple formats in priority order
      [
        ["data_#{locale}.rb", :ruby],
        ["data_#{locale}.json", :json],
        ["data_#{locale}.yml", :yaml],
        ["data_#{locale}.yaml", :yaml],
        ["data/#{locale}.json", :json],
        ["data/#{locale}.yml", :yaml],
        ["data/#{locale}.yaml", :yaml]
      ].each do |filename, format|
        file_path = File.join(base_path, filename)
        next unless File.exist?(file_path)
        
        return case format
        when :ruby
          # Ruby file just returns a hash
          eval(File.read(file_path), binding, file_path)
        when :json
          require 'json'
          JSON.parse(File.read(file_path), symbolize_names: true)
        when :yaml
          require 'yaml'
          # Ruby 2.6+ compatibility
          if YAML.respond_to?(:load_file)
            if RUBY_VERSION >= '2.6'
              YAML.load_file(file_path, symbolize_names: true)
            else
              YAML.load_file(file_path)
            end
          else
            YAML.load(File.read(file_path))
          end
        end
      end
      
      raise Aris::Router::LocaleError, 
        "No data file found for locale :#{locale} in #{base_path}"
    end
    
    # Load template file from handler directory
    # @param name [String] Template filename (default: 'template.html')
    # @return [String] The template content
    # @raise [Aris::Router::LocaleError] If template not found
    def load_template(name = 'template.html')
      file_path = File.join(
        File.dirname(caller_locations.first.path),
        name
      )
      
      if File.exist?(file_path)
        File.read(file_path)
      else
        raise Aris::Router::LocaleError, "Template not found: #{file_path}"
      end
    end
    
    # Render template with data using specified engine
    # @param template_name [String] Name of template file
    # @param data [Hash] Data to interpolate into template
    # @param engine [Symbol] Template engine (:simple or :erb)
    # @return [String] Rendered template
    # @raise [Aris::Router::LocaleError] If template not found or engine unknown
    #
    # NOTE: This is a convenience helper. Handlers can use any template engine.
    def render_template(template_name, data, engine: :simple)
      template_path = File.join(
        File.dirname(caller_locations.first.path),
        template_name
      )
      template = File.read(template_path)
      
      case engine
      when :erb
        require 'erb'
        # Ruby 2.6+ uses result_with_hash, earlier versions need binding
        if ERB.instance_method(:result).parameters.any?
          ERB.new(template).result(binding)
        else
          # For ERB that supports result_with_hash (Ruby 2.5+)
          begin
            ERB.new(template).result_with_hash(data)
          rescue NoMethodError
            # Fallback for older Ruby
            ERB.new(template).result(binding)
          end
        end
      when :simple
        # Simple {{key}} interpolation for basic cases
        template.gsub(/\{\{(\w+)\}\}/) { data[$1.to_sym] || data[$1.to_s] }
      else
        raise Aris::Router::LocaleError, "Unknown template engine: #{engine}"
      end
    rescue Errno::ENOENT
      raise Aris::Router::LocaleError, "Template not found: #{template_path}"
    end
    
    # Declare sitemap metadata (existing method)
    def sitemap(priority: 0.5, changefreq: 'monthly', lastmod: nil, &dynamic)
      @_sitemap_metadata = {
        priority: priority,
        changefreq: changefreq,
        lastmod: lastmod,
        dynamic: dynamic
      }
    end
    
    def sitemap_metadata
      @_sitemap_metadata
    end
    
    # Declare redirect sources (existing method)
    def redirects_from(*paths, status: 301)
      @_redirect_paths = { paths: paths, status: status }
    end
    
    def redirect_metadata
      @_redirect_paths
    end
  end
end