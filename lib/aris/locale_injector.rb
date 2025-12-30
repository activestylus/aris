# lib/aris/locale_injector.rb
module Aris
  module LocaleInjector
    extend self
    
    # Inject locale-aware methods into request object after route matching
    # @param request [Object] The request object (Rack::Request, Mock::Request, etc.)
    # @param match_result [Hash] The route match result containing :locale, :domain
    def inject_locale_methods(request, match_result)
      return unless match_result && match_result[:locale]
      
      locale = match_result[:locale]
      domain = match_result[:domain]
      domain_config = Aris::Router.domain_config(domain)
      
      return unless domain_config
      
      # Inject locale information methods
      request.define_singleton_method(:locale) { locale }
      request.define_singleton_method(:available_locales) { domain_config[:locales] }
      request.define_singleton_method(:default_locale) { domain_config[:default_locale] }
      request.define_singleton_method(:domain_config) { domain_config }
      
      # Inject locale-aware path generation
      request.define_singleton_method(:path_for) do |name, **opts|
        opts[:locale] ||= locale
        opts[:domain] ||= domain
        Aris.path(name, **opts)
      end
      
      # Inject locale-aware URL generation
      request.define_singleton_method(:url_for) do |name, **opts|
        opts[:locale] ||= locale
        opts[:domain] ||= domain
        Aris.url(name, **opts)
      end
    end
  end
end