require 'uri'
require 'set'

module Aris
  @@default_not_found_handler = nil
  @@default_error_handler = nil
  module Config
    class << self
      attr_accessor :trailing_slash, :trailing_slash_status
       attr_accessor :secret_key_base, :cookie_options
      def reset!
        @trailing_slash = :strict
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
  def self.not_found(request, response = nil)
    handler = @@default_not_found_handler
    handler ? handler.call(request, {}) : [404, {'content-type' => 'text/plain'}, ['Not Found']]
  end

  def self.error(request, exception, response = nil)
    handler = @@default_error_handler
    return handler.call(request, exception) if handler
    [500, {'content-type' => 'text/plain'}, ['Internal Server Error']]
  rescue => e
    # Handler itself failed - return fallback
    [500, {'content-type' => 'text/plain'}, ['Internal Server Error']]
  end
  def self.configure
    yield Config
  end


  module Router
    extend self
    HTTP_METHODS = Set[:get, :post, :put, :patch, :delete, :options].freeze

    @@default_domain = nil
    @@default_404_handler = nil
    @@default_500_handler = nil

    
    def default_domain=(domain)
      @@default_domain = domain
    end

    def default_domain
      @@default_domain
    end

    def set_defaults(config)
      @@default_domain = config[:default_host] if config.key?(:default_host)
      Aris.class_variable_set(:@@default_not_found_handler, config[:not_found]) if config.key?(:not_found)
      Aris.class_variable_set(:@@default_error_handler, config[:error]) if config.key?(:error)
    end
        
        def define(config)
      reset!
      compile!(config)
      self
    end
    def domain_config(domain)
      @domain_configs ||= {}
      @domain_configs[domain.to_s]
    end

    def store_domain_config(domain, config)
      @domain_configs ||= {}
      @domain_configs[domain.to_s] = config
    end

    def build_named_path(route_name, domain:, **params)
      route_name = route_name.to_sym
      locale = params.delete(:locale)
      domain_config = self.domain_config(domain)
      
      # If no locale specified but domain has default locale, use it
      if !locale && domain_config && domain_config[:default_locale]
        locale = domain_config[:default_locale]
      end
      
      # For localized routes, always use the base route name and let build_path handle it
      found_metadata = @metadata.values.find do |meta|
        meta[:name] == route_name && meta[:domain] == domain
      end
      
      unless found_metadata
        found_metadata = @metadata.values.find do |meta|
          meta[:name] == route_name && meta[:domain] == '*'
        end
      end
      
      unless found_metadata
        raise RouteNotFoundError.new(route_name, domain)
      end
      
      # If this is a localized route and we have a locale, use locale-aware path building
      if found_metadata[:localized] && locale && domain_config
        build_path_with_locale(found_metadata, params, locale, domain_config)
      else
        build_path_without_locale(found_metadata, params)
      end
    end
    def match(domain:, method:, path:)
      
      return nil if path.start_with?('//') && path != '//'
      normalized_domain = domain.to_s.downcase
      normalized_path = normalize_path(path)
      normalized_method = method.to_sym
      segments = get_path_segments(normalized_path)
      
      match_result = nil
      
      # 1. Try exact domain match first
      domain_trie = @tries[normalized_domain]
      if domain_trie
        match_result = traverse_trie(domain_trie, segments)
      end

      # 2. Try subdomain wildcard match
      unless match_result
        wildcard_domain = find_wildcard_domain_match(normalized_domain)
        
        if wildcard_domain
          domain_trie = @tries[wildcard_domain]
          if domain_trie
            match_result = traverse_trie(domain_trie, segments)
            
            if match_result
              subdomain = extract_subdomain_from_wildcard(normalized_domain, wildcard_domain)
              # Store subdomain in match result
              match_result = [match_result[0], match_result[1], subdomain]
            end
          end
        end
      end

      # 3. Try global wildcard match (existing functionality)
      unless match_result
        wildcard_trie = @tries['*']
        if wildcard_trie
          match_result = traverse_trie(wildcard_trie, segments)
        end
      end

      return nil unless match_result

      node, params, subdomain = match_result
      metadata_key = node[:handlers][normalized_method]
      return nil unless metadata_key

      metadata = @metadata[metadata_key]

      unless enforce_constraints(params, metadata[:constraints]); return nil; end

      route = { 
        name: metadata[:name], 
        handler: metadata[:handler], 
        use: metadata[:use].dup, 
        params: params,
        locale: metadata[:locale],
        domain: normalized_domain
      }
      
      # Add subdomain to route if we matched a wildcard domain
      route[:subdomain] = subdomain if subdomain
      
      route
    end

    private

    def find_wildcard_domain_match(domain)
      # Look through all registered domains for wildcard patterns
      @tries.keys.each do |registered_domain|
        if registered_domain.start_with?('*.')
          base_domain = registered_domain[2..] # Remove '*.'
          
          # Check if the requested domain matches the wildcard pattern
          # Examples:
          # - domain: "acme.example.com" matches "*.example.com" 
          # - domain: "example.com" matches "*.example.com" (no subdomain case)
          if domain == base_domain || domain.end_with?(".#{base_domain}")
            return registered_domain
          end
        end
      end
      nil
    end

    def extract_subdomain_from_wildcard(full_domain, wildcard_domain)
      base_domain = wildcard_domain[2..] # Remove '*.'
      
      if full_domain == base_domain
        # No subdomain (user visited example.com directly)
        nil
      else
        # Extract subdomain by removing the base domain
        # "acme.example.com" -> "acme"
        # "app.staging.example.com" -> "app.staging"  
        full_domain.gsub(".#{base_domain}", '')
      end
    end
    def self.find_domain_config(domain)
      # Exact match first
      exact_match = @domains[domain]
      return exact_match if exact_match
      
      # Then wildcard matches
      @domains.each do |config_domain, config|
        if config_domain.start_with?('*.')
          base_domain = config_domain[2..] # Remove '*.'
          if domain.end_with?(".#{base_domain}") || domain == base_domain
            return config.merge(wildcard: true, base_domain: base_domain)
          end
        end
      end
      
      nil
    end
    
    def build_path(metadata, params)
      build_path_without_locale(metadata, params)
    end

    def build_path_without_locale(metadata, params)
      segments = metadata[:segments].dup
      required_params = metadata[:params]
      provided_params = params.dup
      missing_params = required_params - provided_params.keys
      unless missing_params.empty?
        raise ArgumentError, "Missing required param(s) #{missing_params.map { |p| "'#{p}'" }.join(', ')} for route :#{metadata[:name]}"
      end
      
      path_parts = segments.map do |segment|
        if segment.start_with?(':')
          param_name = segment[1..].to_sym
          value = provided_params.delete(param_name)
          URI.encode_www_form_component(value.to_s)
        elsif segment.start_with?('*')
          param_name = segment[1..].to_s
          param_name = 'path' if param_name.empty?
          value = provided_params.delete(param_name.to_sym)
          value.to_s
        else
          segment
        end
      end
      
      path = path_parts.empty? ? '/' : '/' + path_parts.join('/')
      unless provided_params.empty?
        query_string = URI.encode_www_form(provided_params)
        path += "?#{query_string}"
      end
      path
    end

    def build_path_with_locale(metadata, params, locale, domain_config)
      # Validate locale is available for this domain
      unless domain_config[:locales].include?(locale)
        raise LocaleError, "Locale :#{locale} not available for domain '#{metadata[:domain]}'. Available locales: #{domain_config[:locales].inspect}"
      end
      
      # For localized routes, we need to find the actual locale-specific route metadata
      localized_name = "#{metadata[:name]}_#{locale}".to_sym
      # Find the locale-specific route
      localized_metadata = @metadata.values.find do |meta|
        meta[:name] == localized_name && meta[:domain] == metadata[:domain]
      end
      
      if localized_metadata
        # Use the locale-specific route's segments
        build_path_without_locale(localized_metadata, params)
      else
        # Fallback: build path manually with locale prefix
        base_path = build_path_without_locale(metadata, params)
        if base_path == '/'
          "/#{locale}"
        else
          "/#{locale}#{base_path}"
        end
      end
    end 

    def self.not_found(request, response = nil)
      handler = @@default_not_found_handler
      handler ? handler.call(request, {}) : [404, {'content-type' => 'text/plain'}, ['Not Found']]
    end

    def self.error(request, exception)
      handler = @@default_error_handler
      handler ? handler.call(request, exception) : [500, {'content-type' => 'text/plain'}, ['Internal Server Error']]
    end
    def self.error_response(request, exception)
      handler = @@default_error_handler
      return handler.call(request, exception) if handler
      [500, {'content-type' => 'text/plain'}, ['Internal Server Error']]
    end
    private
    
    def merge_use(parent_use, child_use)
      parent = parent_use.is_a?(Array) ? parent_use : []
      child = child_use.is_a?(Array) ? child_use : []
      (parent + child).uniq
    end

    def reset!
      @tries = {}
      @metadata = {}
      @named_routes = {}
      @route_name_registry = Set.new
      @segment_cache = {}
      @cache_max_size = 1000
      @@default_domain = nil
    end
    def compile!(config)
      @domain_configs = {}
      
      config.each do |domain_key, domain_config|
        domain = domain_key.to_s.downcase
        
        # Store domain configuration (locales, etc.)
        if domain_config.is_a?(Hash) && (domain_config[:locales] || domain_config[:default_locale])
          locales = Array(domain_config[:locales])
          default_locale = domain_config[:default_locale]
          
          # Validate that default_locale is in locales
          if default_locale && !locales.include?(default_locale)
            raise LocaleError, "Default locale '#{default_locale}' not found in locales #{locales.inspect} for domain '#{domain}'"
          end
          
          # Validate that all localized routes use valid locales
          validate_localized_routes(domain_config, locales, domain)
          
          store_domain_config(domain, {
            locales: locales,
            default_locale: default_locale || locales.first,
            root_locale_redirect: domain_config.fetch(:root_locale_redirect, true)
          })
        end
        
        # Handle wildcard domains - store them as-is in tries
        # This preserves the "*.example.com" pattern for matching later
        @tries[domain] = new_trie_node
        
        # Compile routes for this domain (wildcard or regular)
        compile_scope(config: domain_config, domain: domain, path_segments: [], inherited_use: [])
      end
    end

    def validate_localized_routes(domain_config, valid_locales, domain)
      check_config_for_locales(domain_config, valid_locales, domain, '')
    end

    def check_config_for_locales(config, valid_locales, domain, path = '')
      return unless config.is_a?(Hash)
      
      config.each do |key, value|
        if value.is_a?(Hash) && value[:localized]
          invalid_locales = value[:localized].keys - valid_locales
          if invalid_locales.any?
            raise LocaleError, "Handler at #{path}/#{key} uses invalid locales #{invalid_locales.inspect} but domain only supports #{valid_locales.inspect}"
          end
        elsif value.is_a?(Hash)
          # Recursively check nested routes
          check_config_for_locales(value, valid_locales, domain, "#{path}/#{key}")
        end
      end
    end

    def compile_scope(config:, domain:, path_segments:, inherited_use:)
      return unless config.is_a?(Hash)
      
      if config.key?(:use)
        scope_use_value = config[:use]
        if scope_use_value.nil?
          current_use = []
        else
          resolved_scope_use = Array(scope_use_value).flat_map do |item|
            if item.is_a?(Symbol)
              Aris.resolve_plugin(item)  # Returns array of classes
            else
              item
            end
          end
          current_use = merge_use(inherited_use, resolved_scope_use)
        end
      else
        current_use = inherited_use.is_a?(Array) ? inherited_use : []
      end
      config.each do |key, value|
        next if key == :use
        if HTTP_METHODS.include?(key)
          register_route(domain: domain, method: key, path_segments: path_segments, route_config: value, inherited_use: current_use)
        elsif key.is_a?(String) || key.is_a?(Symbol)
            new_segments = parse_path_key(key.to_s)
          compile_scope(config: value, domain: domain, path_segments: path_segments + new_segments, inherited_use: current_use)
        end
      end
    end

    def register_route(domain:, method:, path_segments:, route_config:, inherited_use:)
      name = route_config[:as]
      handler = route_config[:to]
      constraints = route_config[:constraints] || {}
      route_use_unresolved = route_config[:use]
      localized_paths = route_config[:localized]
      
      resolved_inherited = Array(inherited_use).flat_map do |item|
        if item.is_a?(Symbol)
          Aris.resolve_plugin(item)
        else
          item
        end
      end
      
      if route_use_unresolved
        resolved_route_use = Array(route_use_unresolved).flat_map do |item|
          if item.is_a?(Symbol)
            Aris.resolve_plugin(item)
          else
            item
          end
        end
        route_use = resolved_route_use
      else
        route_use = nil
      end
      
      if route_use
        final_use = merge_use(resolved_inherited, route_use)
      else
        final_use = resolved_inherited
      end
      
      # Handle localized routes
      if localized_paths && !localized_paths.empty?
        domain_config = self.domain_config(domain)
        if domain_config && domain_config[:locales]
          # Warn about missing locales (routes that don't cover all domain locales)
          missing_locales = domain_config[:locales] - localized_paths.keys
          if missing_locales.any?
            warn "Warning: Route '#{build_pattern(path_segments)}' missing locales: #{missing_locales.inspect}"
          end
          
          # Register the base route for URL generation (without locale prefix)
          if name
            @route_name_registry.add(name)
            base_metadata_key = build_metadata_key(domain, method, build_pattern(path_segments))
            @metadata[base_metadata_key] = {
              domain: domain,
              name: name,
              handler: handler,
              use: final_use,
              pattern: build_pattern(path_segments),
              params: extract_param_names(path_segments),
              segments: path_segments.dup,
              constraints: constraints,
              localized: true
            }
            @named_routes[name] = base_metadata_key
          end
          
          # Register locale-specific routes (with locale prefix and localized segment)
          localized_paths.each do |locale, localized_path|
            if domain_config[:locales].include?(locale)
              # Parse the localized path (e.g., "about" or "products/:id")
              localized_segments = parse_path_key(localized_path.to_s)
              
              # Combine: locale + localized_segments
              full_path_segments = [locale.to_s] + localized_segments
              
              register_localized_route(
                domain: domain,
                method: method,
                path_segments: full_path_segments,
                route_config: route_config,
                inherited_use: final_use,
                name: name,
                handler: handler,
                constraints: constraints,
                locale: locale
              )
            else
              raise LocaleError, "Locale '#{locale}' not found in domain '#{domain}' locales: #{domain_config[:locales].inspect}"
            end
          end
        end
        return
      end
      
      # Original registration for non-localized routes
      if name
        if @route_name_registry.include?(name)
          existing = @named_routes[name]
          existing_meta = @metadata[existing]
          raise DuplicateRouteNameError.new(
            name: name,
            existing_domain: existing_meta[:domain],
            existing_pattern: existing_meta[:pattern],
            new_domain: domain,
            new_pattern: build_pattern(path_segments)
          )
        end
        @route_name_registry.add(name)
      end
      
      pattern = build_pattern(path_segments)
      param_names = extract_param_names(path_segments)
      metadata_key = build_metadata_key(domain, method, pattern)
      @metadata[metadata_key] = {
        domain: domain,
        name: name,
        handler: handler,
        use: final_use,
        pattern: pattern,
        params: param_names,
        segments: path_segments.dup,
        constraints: constraints
      }
      @named_routes[name] = metadata_key if name
      insert_into_trie(domain, path_segments, method, metadata_key)
    end

    def register_localized_route(domain:, method:, path_segments:, route_config:, inherited_use:, name:, handler:, constraints:, locale:)
      # Create locale-specific name
      localized_name = name ? "#{name}_#{locale}".to_sym : nil
      
      if localized_name && @route_name_registry.include?(localized_name)
        existing = @named_routes[localized_name]
        existing_meta = @metadata[existing]
        raise DuplicateRouteNameError.new(
          name: localized_name,
          existing_domain: existing_meta[:domain],
          existing_pattern: existing_meta[:pattern],
          new_domain: domain,
          new_pattern: build_pattern(path_segments)
        )
      end
      
      # DO NOT add locale prefix here - the path_segments already include it from the route config
      pattern = build_pattern(path_segments)
      param_names = extract_param_names(path_segments)
      metadata_key = build_metadata_key(domain, method, pattern)
      
      @metadata[metadata_key] = {
        domain: domain,
        name: localized_name,
        handler: handler,
        use: inherited_use,
        pattern: pattern,
        params: param_names,
        segments: path_segments.dup,
        constraints: constraints,
        locale: locale
      }
      
      @route_name_registry.add(localized_name) if localized_name
      @named_routes[localized_name] = metadata_key if localized_name
      insert_into_trie(domain, path_segments, method, metadata_key)
    end
    def enforce_constraints(params, constraints)
      constraints.each do |param_name, regex|
        value = params[param_name] 
        if value && !value.match?(regex)
          return false
        end
      end
      true
    end
    def extract_use(config)
      return nil unless config.is_a?(Hash)
      return nil unless config.key?(:use)
      use_value = config[:use]
      return [] if use_value.nil?
      Array(use_value)
    end

    def new_trie_node
      { literal_children: {}, param_child: nil, wildcard_child: nil, handlers: {} }
    end

    def insert_into_trie(domain, path_segments, method, metadata_key)
      node = @tries[domain]
      path_segments.each { |segment| node = insert_segment(node, segment) }
      node[:handlers][method] = metadata_key
    end

    def insert_segment(node, segment)
      if segment.start_with?('*')
        wildcard_name = segment[1..].to_s
        wildcard_name = 'path' if wildcard_name.empty?
        unless node[:wildcard_child]
          node[:wildcard_child] = { name: wildcard_name.to_sym, node: new_trie_node }
        end
        node[:wildcard_child][:node]
      elsif segment.start_with?(':')
        param_name = segment[1..].to_sym
        unless node[:param_child]
          node[:param_child] = { name: param_name, node: new_trie_node }
        end
        node[:param_child][:node]
      else
        node[:literal_children][segment] ||= new_trie_node
      end
    end

    def traverse_trie(node, segments, params = {})
      return nil unless node
      return [node, params] if segments.empty?
      current_segment = segments.first
      remaining_segments = segments[1..]
      if node[:literal_children][current_segment]
        result = traverse_trie(node[:literal_children][current_segment], remaining_segments, params)
        return result if result
      end
      if node[:param_child]
        param_name = node[:param_child][:name]
        params[param_name] = current_segment
        result = traverse_trie(node[:param_child][:node], remaining_segments, params)
        if result
          return result
        else
            params.delete(param_name)
        end
      end
      if node[:wildcard_child]
        wildcard_name = node[:wildcard_child][:name]
        (0..segments.size).each do |i|
          captured_segments = segments[0..i]
          remaining_after_wildcard = segments[(i + 1)..] || []
          captured_path = captured_segments.join('/')
          params[wildcard_name] = captured_path
          result = traverse_trie(node[:wildcard_child][:node], remaining_after_wildcard, params)
          if result
            return result
          else
            params.delete(wildcard_name)
          end
        end
      end
      nil
    end

    def build_path(metadata, params)
      segments = metadata[:segments].dup
      required_params = metadata[:params]
      provided_params = params.dup
      missing_params = required_params - provided_params.keys
      unless missing_params.empty?
        raise ArgumentError, "Missing required param(s) #{missing_params.map { |p| "'#{p}'" }.join(', ')} for route :#{metadata[:name]}"
      end
      path_parts = segments.map do |segment|
        if segment.start_with?(':')
          param_name = segment[1..].to_sym
          value = provided_params.delete(param_name)
          URI.encode_www_form_component(value.to_s)
        elsif segment.start_with?('*')
          param_name = segment[1..].to_s
          param_name = 'path' if param_name.empty?
          value = provided_params.delete(param_name.to_sym)
          value.to_s
        else
          segment
        end
      end
      path = path_parts.empty? ? '/' : '/' + path_parts.join('/')
      unless provided_params.empty?
        query_string = URI.encode_www_form(provided_params)
        path += "?#{query_string}"
      end
      path
    end

    def parse_path_key(key)
      key.split('/').reject(&:empty?)
    end

    def build_pattern(segments)
      segments.empty? ? '/' : '/' + segments.join('/')
    end

    def extract_param_names(segments)
      segments.select { |s| s.start_with?(':') || s.start_with?('*') }.map { |s| s[1..].to_sym }
    end

    def build_metadata_key(domain, method, pattern)
      "#{domain}:#{method.to_s.upcase}:#{pattern}"
    end

    def get_path_segments(normalized_path)
      if cached = @segment_cache[normalized_path]
        return cached
      end
      
      if normalized_path == '/'
        segments = []
      else
        segments = normalized_path.split('/').reject(&:empty?)
        
        # In strict mode, preserve trailing slash by appending to last segment
        if Aris::Config.trailing_slash == :strict && 
           normalized_path.end_with?('/') && 
           normalized_path != '/' && 
           segments.any?
          segments[-1] = segments[-1] + '/'
        end
      end
      
      if @segment_cache.size >= @cache_max_size
        @segment_cache.clear
      end
      @segment_cache[normalized_path] = segments
      segments
    end
    def normalize_path(path)
      return '/' if path.empty?
      return path if path == '/' || (path == '/users' && !path.include?('//'))
      
      if path.include?('//')
        path = path.gsub(%r{/+}, '/')
      end
      
      # Don't strip trailing slash in strict mode
      normalized = if Aris::Config.trailing_slash == :strict
        path  # Keep trailing slash in strict mode
      else
        path.length > 1 && path.end_with?('/') ? path.chomp('/') : path
      end
      
      if normalized.include?('%')
        begin
          normalized = URI.decode_www_form_component(normalized)
        rescue
        end
      end
      
      normalized.downcase
    end
    class RouteNotFoundError < StandardError
      def initialize(name, domain)
        # FIX: Concatenate arguments into a single string before calling super
        super("Named route :#{name} not found on domain '#{domain}' or '*' fallback.")
      end
    end
    class DuplicateRouteNameError < StandardError
    end
    class LocaleError < StandardError
      def initialize(message)
        super(message)
      end
    end
  end

  module CurrentDomain
    extend self
    THREAD_KEY = :aris_current_domain
    def current
      Thread.current[THREAD_KEY] || 
        Aris::Router.default_domain || 
        raise("No domain context available. Set Thread.current[:aris_current_domain] or Aris::Router.default_domain")
    end
    
    def with_domain(domain, &block)
      original = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = domain
      yield
    ensure
      Thread.current[:aris_current_domain] = original
    end
  end

  module PathHelper
    extend self

    def extract_domain_and_route(args)
      case args.size
      when 1
        [CurrentDomain.current, args[0]]
      when 2
        [args[0].to_s.downcase, args[1]]
      else
        raise ArgumentError, "Expected 1 or 2 arguments, got #{args.size}"
      end
    end
    
    def call(*args, **params)
      domain, route_name = extract_domain_and_route(args)
      clean_domain = domain.to_s.sub(%r{^https?://}, '').downcase
      Aris::Router.build_named_path(route_name, domain: clean_domain, **params)
    end
  end

  module URLHelper
    extend self
    def call(*args, protocol: 'https', **params)
      domain, route_name = PathHelper.extract_domain_and_route(args)
      path = PathHelper.call(*args, **params)
      clean_assembly_domain = domain.sub(%r{^https?://}, '')
      "#{protocol}://#{clean_assembly_domain}#{path}"
    end
  end

  private

  def extract_domain_and_route(args)
    case args.size
    when 1
      [CurrentDomain.current, args[0]]
    when 2
      [args[0].to_s.downcase, args[1]]
    else
      raise ArgumentError, "Expected 1 or 2 arguments, got #{args.size}"
    end
  end
  
  def current_domain
    CurrentDomain.current
  end

  def handle_trailing_slash(path)
    mode = Config.trailing_slash
    
    return [nil, path] if mode == :strict
    return [nil, path] unless path.end_with?('/')
    return [nil, path] if path == '/'  # Root path exception
    
    normalized = path.chomp('/')
    
    case mode
    when :redirect
      [[Config.trailing_slash_status, {'Location' => normalized}, []], nil]
    when :ignore
      [nil, normalized]
    else
      [nil, path]
    end
  end

  def path(*args, **kwargs)
    domain_to_match, route_name = PathHelper.extract_domain_and_route(args) 
    clean_domain = domain_to_match.sub(%r{^https?://}, '').downcase
    Router.build_named_path(route_name, domain: clean_domain, **kwargs)
  end

  def url(*args, protocol: 'https', **kwargs)
    domain_to_assemble = if args.size == 2
      args[0].to_s
    else
      current_domain
    end
    path = self.path(*args, **kwargs)
    clean_assembly_domain = domain_to_assemble.sub(%r{^https?://}, '')
    "#{protocol}://#{clean_assembly_domain}#{path}"
  end
  
  def with_domain(domain, &block)
    CurrentDomain.with_domain(domain, &block)
  end
  def default(config); Router.set_defaults(config); end

  def redirect(target, status: 302, **params)
    url = if target.is_a?(Symbol)
      self.url(target, **params)
    else
      target.to_s
    end
    [status, {'content-type' => 'text/plain', 'Location' => url}, []]
  end

  def routes(config = nil, from_discovery: false, **kwargs)
    # Ruby 3 compatibility: if config is nil and kwargs present, treat kwargs as config
    config = kwargs if config.nil? && !kwargs.empty?
    
    if config.nil? || (!config.is_a?(Hash) && kwargs.empty?)
      raise ArgumentError, "Aris.routes requires a configuration hash."
    end
    
    unless from_discovery
      Aris::Utils::Sitemap.reset! if defined?(Aris::Utils::Sitemap)
      Aris::Utils::Redirects.reset! if defined?(Aris::Utils::Redirects)
      extract_utils_metadata(config) if config.is_a?(Hash)
    end
    
    raise ArgumentError, "Aris.routes requires a configuration hash." unless config.is_a?(Hash)
    Router.define(config)
  end
  def extract_utils_metadata(routes_hash, domain: nil, path_parts: [])
    return unless routes_hash.is_a?(Hash)
    
    # Store domain config if present
    if domain && (routes_hash[:locales] || routes_hash[:default_locale])
      Aris::Router.store_domain_config(domain, {
        locales: Array(routes_hash[:locales]),
        default_locale: routes_hash[:default_locale],
        root_locale_redirect: routes_hash.fetch(:root_locale_redirect, true)
      })
    end
    
    routes_hash.each do |key, value|
      next unless value.is_a?(Hash)
      
      if key.is_a?(Symbol) && [:get, :post, :put, :patch, :delete, :options].include?(key)
        path = path_parts.empty? ? '/' : path_parts.join('')
        
        if defined?(Aris::Utils::Sitemap) && value[:sitemap]
          Aris::Utils::Sitemap.register(domain: domain, path: path, method: key, metadata: value[:sitemap])
        end
        
        if defined?(Aris::Utils::Redirects) && value[:redirects_from]
          Aris::Utils::Redirects.register(from_paths: value[:redirects_from], to_path: path, status: value[:redirect_status] || 301)
        end
      else
        new_domain = domain || key.to_s
        new_path = domain ? path_parts + [key.to_s] : path_parts
        extract_utils_metadata(value, domain: new_domain, path_parts: new_path)
      end
    end
  end
  module_function :path, :url, :with_domain, :current_domain, :routes, :default, :redirect, :extract_utils_metadata, :handle_trailing_slash
end