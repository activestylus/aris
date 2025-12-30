# lib/aris/adapters/mock/adapter.rb
require_relative '../../core'
require_relative '../../pipeline_runner'
require_relative 'request'
require_relative 'response'
require 'json'

module Aris
  module Adapters
    module Mock
      class Adapter
        def call(method:, path:, domain:, headers: {}, body: '', query: '')
          # Parse cookies from headers before creating request
          cookies = parse_cookies(headers)
          
          request = Request.new(
            method: method,
            path: path,
            domain: domain,
            headers: headers,
            body: body,
            query: query,
            cookies: cookies  # Add cookies
          )
          
          request_domain = request.host
          Thread.current[:aris_current_domain] = request_domain
          
          begin
            redirect_response, normalized_path = Aris.handle_trailing_slash(path)
            if redirect_response
              return { 
                status: redirect_response[0], 
                headers: redirect_response[1], 
                body: redirect_response[2] 
              }
            end
            domain_config = Aris::Router.domain_config(domain)
            if domain_config && domain_config[:locales] && domain_config[:locales].any? && domain_config[:root_locale_redirect] != false
              if path == '/' || path.empty?
                default_locale = domain_config[:default_locale] || domain_config[:locales].first
                return { status: 302, headers: {'Location' => "/#{default_locale}/"}, body: [] }
              end
            end
            
            if defined?(Aris::Utils::Sitemap) && path == '/sitemap.xml'
              xml = Aris::Utils::Sitemap.generate(base_url: "https://#{domain}", domain: domain)
              return { status: 200, headers: {'content-type' => 'application/xml'}, body: [xml] }
            end
            
            # Check redirects
            if defined?(Aris::Utils::Redirects)
              redirect = Aris::Utils::Redirects.find(path)
              if redirect
                return { status: redirect[:status], headers: {'Location' => redirect[:to]}, body: [] }
              end
            end
            
            route = Aris::Router.match(
              domain: request_domain,
              method: request.request_method.downcase.to_sym,
              path: request.path_info
            )

            unless route
              return format_response(Aris.not_found(request))
            end
            
            # Inject locale methods into request if locale is present
            if route[:locale]
              request.define_singleton_method(:locale) { route[:locale] }
              if domain_config
                request.define_singleton_method(:available_locales) { domain_config[:locales] }
                request.define_singleton_method(:default_locale) { domain_config[:default_locale] }
              end
            end
            
            response = Response.new
            request.instance_variable_set(:@response, response)
            request.define_singleton_method(:response) { @response }
            # Execute plugins and handler via PipelineRunner
            result = PipelineRunner.call(request: request, route: route, response: response)
            
            # Format the result
            format_response(result, response)

          rescue Aris::Router::RouteNotFoundError
            return format_response(Aris.not_found(request))
          rescue Exception => e
            return format_response(Aris.error(request, e))
          ensure
            Thread.current[:aris_current_domain] = nil
          end
        end

        def subdomain
          @subdomain || extract_subdomain_from_domain
        end

        private

        def extract_subdomain_from_domain
          return nil unless @env[:subdomain] || @env['SUBDOMAIN']
          
          @env[:subdomain] || @env['SUBDOMAIN']
        end

        def parse_cookies(headers)
          return {} unless headers && headers['Cookie']
          
          cookies = {}
          headers['Cookie'].split(';').each do |cookie|
            name, value = cookie.strip.split('=', 2)
            cookies[name] = value if name && value
          end
          cookies
        end

def format_response(result, response = nil)
  case result
  when Response
    { status: result.status, headers: result.headers, body: result.body }
  when Array
    # Don't unwrap - keep body as-is
    { status: result[0], headers: result[1], body: result[2] }
  when Hash
    headers = response ? response.headers.merge({'content-type' => 'application/json'}) : {'content-type' => 'application/json'}
    { status: 200, headers: headers, body: [result.to_json] }
  else
    if result.respond_to?(:status) && result.respond_to?(:headers) && result.respond_to?(:body)
      { status: result.status, headers: result.headers, body: result.body }
    else
      headers = response ? response.headers.merge({'content-type' => 'text/plain'}) : {'content-type' => 'text/plain'}
      { status: 200, headers: headers, body: [result.to_s] }
    end
  end
end
      end
    end
  end
end