# lib/aris/adapters/rack/adapter.rb
require_relative '../../core'
require_relative '../../pipeline_runner'
require_relative '../base'
require_relative 'request'
require_relative 'response'
require 'json'

module Aris
  module Adapters
    class RackApp < Base 
      def initialize(app = nil)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
          static_response = handle_static(request)
          return static_response if static_response
          
          sitemap_response = handle_sitemap(request)
          return sitemap_response if sitemap_response
          
          redirect_response = handle_redirect(request)
          return redirect_response if redirect_response
          
          redirect_res, normalized_path = Aris.handle_trailing_slash(request.path_info)
          return redirect_res if redirect_res
        
        # return res if res = handle_static(request)
        # return res if res = handle_sitemap(request)
        # return res if res = handle_redirect(request)
        # redirect_res, normalized_path = Aris.handle_trailing_slash(request.path_info)
        # return redirect_res if redirect_res
        
        path_for_matching = normalized_path || request.path_info
        
        request_domain = request.host
        Thread.current[:aris_current_domain] = request_domain
        
        response = Rack::Response.new
        request.instance_variable_set(:@response, response)
        request.define_singleton_method(:response) { @response }

        begin
          domain_config = Aris::Router.domain_config(request_domain)
          route = Aris::Router.match(
            domain: request_domain,
            method: request.request_method.downcase.to_sym,
            path: path_for_matching
          )
          if route
            inject_locale_methods(request, route, domain_config)
            result = PipelineRunner.call(request: request, route: route, response: response)
            format_response(result, response)
          else
            format_response(Aris.not_found(request, response), response)
          end

        rescue Aris::Router::RouteNotFoundError
          format_response(Aris.not_found(request, response), response)
        rescue Exception => e
          # Error Path: 500
          format_response(Aris.error(request, e), response)

        ensure
          Thread.current[:aris_current_domain] = nil
        end
      end
    
      def subdomain
        @subdomain || extract_subdomain_from_domain
      end

      private
      def handle_static(request)
        return nil unless request.request_method == 'GET'
        return nil unless Aris::Config.serve_static
        
        path = File.join('public', request.path_info)
        return nil unless File.file?(path)
        
        [200, 
          {
            'content-type' => mime_type(path),
            'cache-control' => 'public, max-age=31536000'
          }, 
          [File.binread(path)]
        ]
      end

      def mime_type(path)
        ext = File.extname(path).downcase
        Aris::Config.mime_types[ext] || 'application/octet-stream'
      end


      def extract_subdomain_from_domain
        return nil unless @env[:subdomain] || @env['SUBDOMAIN']
        
        @env[:subdomain] || @env['SUBDOMAIN']
      end


      def inject_locale_methods(request, route, domain_config)
        return unless route[:locale]

        # Inject the locale helper
        request.define_singleton_method(:locale) { route[:locale] }
        
        # Inject domain-specific locale configuration if it exists
        if domain_config
          request.define_singleton_method(:available_locales) { domain_config[:locales] }
          request.define_singleton_method(:default_locale) { domain_config[:default_locale] }
        end
      end
      def handle_sitemap(request)
        # Overridden by sitemap utils if loaded
        nil
      end

      def handle_redirect(request)
        # Overridden by redirects utils if loaded  
        nil
      end

      def format_response(result, response = nil)
        # 1. Identify the 'active' response source
        # We check the passed object (response) and the returned object (result)
        active_res = if result.respond_to?(:body) && !Array(result.body).empty?
                       result
                     elsif response.respond_to?(:body) && !Array(response.body).empty?
                       response
                     else
                       nil
                     end

        # 2. If we found a response with content, send it to the Rack server
        if active_res
          # Standardize the body as an Array of Strings for Rack 3 compatibility
          body = active_res.body
          body = [body] if body.is_a?(String)
          
          return [active_res.status, active_res.headers, body]
        end

        # 3. Final Fallback (If Joys rendered nothing)
        case result
        when Array then result
        when Hash  then [200, {'content-type' => 'application/json'}, [result.to_json]]
        else            [200, {'content-type' => 'text/plain'}, [result.to_s]]
        end
      end


    end
  end
end