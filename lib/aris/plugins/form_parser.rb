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
      
def call(request, response)
  return nil unless PARSEABLE_METHODS.include?(request.method)
  
  # Check content-type - access from env, not headers
  content_type = request.env['CONTENT_TYPE']
  return nil unless content_type&.include?('application/x-www-form-urlencoded')
  
  raw_body = request.body
  return nil if raw_body.nil? || raw_body.empty?
  
  begin
    # Parse form data
    data = ::Rack::Utils.parse_nested_query(raw_body)
    
    # Attach parsed data to request
    request.instance_variable_set(:@form_data, data)
  rescue => e
    response.status = 400
    response.headers['content-type'] = 'text/plain'
    response.body = ['Invalid form data']
    return response
  end
  
  nil # Continue pipeline
end
      
      def self.build(**config)
        new(**config)
      end
    end
  end
end
