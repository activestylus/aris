# lib/aris/discovery.rb
require 'pathname'

module Aris
  module Discovery
    extend self

    HTTP_METHODS = Set[:get, :post, :put, :patch, :delete, :options].freeze

    # Scans a directory and generates an Aris routes hash with locale support
    # Handlers are LOADED during discovery, not at request time
    def discover(routes_dir, namespace_handlers: true)
      base_path = Pathname.new(routes_dir).realpath
      routes = {}
      domain_configs = {}
      
      # First pass: discover domain configs
      Dir.glob("#{routes_dir}/*/_config.rb").sort.each do |config_file|
        domain_name = File.basename(File.dirname(config_file))
        domain_key = (domain_name == '_') ? '*' : domain_name
        
        config = discover_domain_config(config_file)
        domain_configs[domain_key] = config if config
      end
      
      # Second pass: discover route files
      Dir.glob("#{routes_dir}/**/*.rb").sort.each do |file_path|
        next if file_path.end_with?('_config.rb')
        
        route_info = parse_route_file(file_path, base_path)
        next unless route_info
        
        # Load the handler NOW (at boot time, not request time)
        handler = load_handler(file_path, route_info, namespace_handlers)
        next unless handler
        
        # Check for localized declaration
        localized_paths = discover_handler_locales(handler)
        
        # If handler has localized declaration, validate against domain config
        if localized_paths && !localized_paths.empty?
          domain_config = domain_configs[route_info[:domain]]
          
          if domain_config
            validate_localized_handler(
              handler_path: File.dirname(file_path),
              localized_paths: localized_paths,
              domain_config: domain_config,
              route_info: route_info
            )
          else
            warn "Warning: Handler at #{file_path} declares localized paths but domain has no _config.rb"
          end
        end
        
        # Build the nested route structure
        add_route_to_hash(routes, route_info, handler, localized_paths)
      end
      
      # Merge domain configs into routes
      domain_configs.each do |domain, config|
        routes[domain] ||= {}
        routes[domain][:locales] = config[:locales]
        routes[domain][:default_locale] = config[:default_locale]
        routes[domain][:root_locale_redirect] = config[:root_locale_redirect] if config.key?(:root_locale_redirect)
      end
      
      routes
    end

    private

    # Discover domain configuration from _config.rb file
    def discover_domain_config(config_file)
      load config_file
      
      # Look for DomainConfig module
      if defined?(DomainConfig)
        config = {
          locales: DomainConfig::LOCALES,
          default_locale: DomainConfig::DEFAULT_LOCALE
        }
        
        # Optional root redirect configuration
        if DomainConfig.const_defined?(:ROOT_LOCALE_REDIRECT)
          config[:root_locale_redirect] = DomainConfig::ROOT_LOCALE_REDIRECT
        end
        
        # Clean up to avoid conflicts with next domain
        Object.send(:remove_const, :DomainConfig)
        
        return config
      end
      
      nil
    rescue => e
      warn "Error loading domain config from #{config_file}: #{e.message}"
      nil
    end

    # Parse file path into route information
    def parse_route_file(file_path, base_path)
      absolute_path = Pathname.new(file_path).realpath
      relative_path = absolute_path.relative_path_from(base_path)
      parts = relative_path.to_s.split('/')
      
      return nil if parts.size < 2 # Need at least domain/method.rb
      
      # Extract method from filename
      method_file = parts.pop
      method_name = File.basename(method_file, '.rb').downcase.to_sym
      return nil unless HTTP_METHODS.include?(method_name)
      
      # Extract domain
      domain_name = parts.shift
      domain_key = (domain_name == '_') ? '*' : domain_name
      
      # Build path segments, converting _param to :param
      path_parts = parts.reject { |p| p == 'index' }
                        .map { |p| p.start_with?('_') ? ":#{p[1..]}" : "/#{p}" }
      
      {
        domain: domain_key,
        path_parts: path_parts,
        method: method_name,
        file_path: absolute_path.to_s,
        namespace: build_namespace(domain_key, path_parts, method_name)
      }
    end

    # Build a namespace for the handler to avoid conflicts
    # e.g., "example.com/users/:id", :get -> ExampleCom::Users::Id::Get
    def build_namespace(domain, path_parts, method)
      # Convert * to Wildcard for valid module name
      domain_part = domain == '*' ? 'Wildcard' : domain.gsub(/[^a-zA-Z0-9]/, '_')
      parts = [domain_part]
      parts += path_parts.map do |p|
        p.sub('/', '').sub(':', '').gsub(/[^a-zA-Z0-9]/, '_')
      end
      parts << method.to_s  # Add method to ensure unique namespace
      parts.map(&:capitalize).join('::')
    end

    # Load handler from file and namespace it to avoid conflicts
    def load_handler(file_path, route_info, namespace_handlers)
      if namespace_handlers
        # Create a module namespace for this specific route
        namespace_module = create_namespace_module(route_info[:namespace])
        
        # Evaluate the file within that namespace
        code = File.read(file_path)
        namespace_module.module_eval(code, file_path)
        
        # Look for Handler constant in the namespace
        if namespace_module.const_defined?(:Handler, false)
          handler = namespace_module.const_get(:Handler)
          validate_handler!(handler, file_path)
          return handler
        else
          warn "Warning: #{file_path} does not define a Handler constant"
          return nil
        end
      else
        # Load file and grab top-level Handler (simpler but risks conflicts)
        load file_path
        
        if Object.const_defined?(:Handler, false)
          handler = Object.const_get(:Handler)
          Object.send(:remove_const, :Handler) # Clean up to avoid next file's conflict
          validate_handler!(handler, file_path)
          return handler
        else
          warn "Warning: #{file_path} does not define a Handler constant"
          return nil
        end
      end
    rescue SyntaxError => e
      warn "Syntax error in #{file_path}: #{e.message}"
      nil
    rescue => e
      warn "Error loading handler from #{file_path}: #{e.message}"
      nil
    end

    # Create nested module namespace
    def create_namespace_module(namespace_string)
      parts = namespace_string.split('::')
      parts.reduce(Object) do |parent, part|
        if parent.const_defined?(part, false)
          parent.const_get(part)
        else
          parent.const_set(part, Module.new)
        end
      end
    end

    # Validate handler has required interface
    def validate_handler!(handler, file_path)
      unless handler.respond_to?(:call)
        raise ArgumentError, 
              "Handler in #{file_path} must respond to .call(request, params)"
      end
    end

    # Check if handler declares localized paths
    def discover_handler_locales(handler)
      if handler.respond_to?(:localized_paths)
        handler.localized_paths
      else
        nil
      end
    end

    # Validate localized handler against domain config
    def validate_localized_handler(handler_path:, localized_paths:, domain_config:, route_info:)
      domain_locales = domain_config[:locales]
      handler_locales = localized_paths.keys
      
      # Error: handler uses locale not in domain config
      invalid_locales = handler_locales - domain_locales
      if invalid_locales.any?
        raise Aris::Router::LocaleError,
          "Handler at #{handler_path} uses locales #{invalid_locales.inspect} " +
          "but domain only declares #{domain_locales.inspect}"
      end
      
      # Warning: handler missing some domain locales
      missing_locales = domain_locales - handler_locales
      if missing_locales.any?
        warn "Warning: Handler at #{handler_path} missing locales: #{missing_locales.inspect}"
      end
      
      # Validate data files exist
      validate_data_files(handler_path, handler_locales)
    end

    # Validate data files exist for each locale
    def validate_data_files(handler_path, locales)
      locales.each do |locale|
        found = [
          "data_#{locale}.rb",
          "data_#{locale}.json",
          "data_#{locale}.yml",
          "data_#{locale}.yaml",
          "data/#{locale}.json",
          "data/#{locale}.yml",
          "data/#{locale}.yaml"
        ].any? { |f| File.exist?(File.join(handler_path, f)) }
        
        unless found
          warn "Warning: Missing data file for locale :#{locale} in #{handler_path}"
        end
      end
    end

    # Add route to nested hash structure
    def add_route_to_hash(routes, route_info, handler, localized_paths)
      domain = route_info[:domain]
      routes[domain] ||= {}
      
      current_level = routes[domain]
      
      # Navigate/create nested path structure
      route_info[:path_parts].each do |part|
        current_level[part] ||= {}
        current_level = current_level[part]
      end
      
      # Handle root path (no path parts)
      if route_info[:path_parts].empty?
        current_level['/'] ||= {}
        current_level = current_level['/']
      end
      
      # Build route definition
      route_def = { to: handler }
      
      # Add localized paths if declared
      if localized_paths && !localized_paths.empty?
        route_def[:localized] = localized_paths
      end
      
      # Add the route
      current_level[route_info[:method]] = route_def
  
      # Now register metadata AFTER route is added
      if defined?(Aris::Utils::Sitemap) && handler.respond_to?(:sitemap_metadata) && handler.sitemap_metadata
        path = route_info[:path_parts].empty? ? '/' : route_info[:path_parts].join('')
        Aris::Utils::Sitemap.register(
          domain: route_info[:domain],
          path: path,
          method: route_info[:method],
          metadata: handler.sitemap_metadata
        )
      end
      
      if defined?(Aris::Utils::Redirects) && handler.respond_to?(:redirect_metadata) && handler.redirect_metadata
        path = route_info[:path_parts].empty? ? '/' : route_info[:path_parts].join('')
        Aris::Utils::Redirects.register(
          from_paths: handler.redirect_metadata[:paths],
          to_path: path,
          status: handler.redirect_metadata[:status]
        )
      end
    end
  end

  def self.discover_and_define(routes_dir, namespace_handlers: true)
    discovered = Discovery.discover(routes_dir, namespace_handlers: namespace_handlers)
    self.routes(discovered, from_discovery: true)
  end
end