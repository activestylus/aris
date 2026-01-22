# lib/aris/plugins/form_parser.rb
require 'rack/utils'

module Aris
  module Plugins
    class FormParser
      attr_reader :config
      
      PARSEABLE_METHODS = %w[POST PUT PATCH].freeze
      
      def initialize(**config)
        @config = config
      end
      
def self.call(request, response)
  return nil unless PARSEABLE_METHODS.include?(request.method)
  
  content_type = request.env['CONTENT_TYPE']
  return nil unless content_type&.include?('application/x-www-form-urlencoded')
  
  raw_body = request.body
  return nil if raw_body.nil? || raw_body.empty?
  
  begin
    data = ::Rack::Utils.parse_nested_query(raw_body)
    request.instance_variable_set(:@parsed_form_data, data)
    
    # Add clean accessor method
    request.define_singleton_method(:form_params) do
      @parsed_form_data || {}
    end
    
  rescue => e
    response.status = 400
    response.headers['content-type'] = 'text/plain'
    response.body = ['Invalid form data']
    return response
  end
  
  nil
end
      
      def self.build(**config)
        new(**config)
      end
    end
  end
end
Aris.register_plugin(:form_parser, plugin_class: Aris::Plugins::FormParser)
