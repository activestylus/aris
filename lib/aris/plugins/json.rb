require 'json'

module Aris
  module Plugins
    class Json
      PARSEABLE_METHODS = %w[POST PUT PATCH].freeze
      
      def self.call(request, response)
        return nil unless PARSEABLE_METHODS.include?(request.method)
        
        raw_body = request.body
        return nil if raw_body.nil? || raw_body.empty?
        
        begin
          data = JSON.parse(raw_body)
          # Attach parsed data to request
          request.json_body = data
        rescue JSON::ParserError => e
          response.status = 400
          response.headers['content-type'] = 'application/json'
          response.body = [JSON.generate({ error: 'Invalid JSON', message: e.message })]
          return response # Halt pipeline
        end
        
        nil # Continue pipeline
      end
    end
  end
end

# Self-register
Aris.register_plugin(:json, plugin_class: Aris::Plugins::Json)