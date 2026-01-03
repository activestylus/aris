require 'uri'
require 'set'

module Aris
  @@default_not_found_handler = nil
  @@default_error_handler = nil

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
      [[Config.trailing_slash_status, {'location' => normalized}, []], nil]
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
    [status, {'content-type' => 'text/plain', 'location' => url}, []]
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