# lib/aris/plugins/request_id.rb
require 'securerandom'

module Aris
  module Plugins
    class RequestId
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @header_name = config[:header_name] || 'X-Request-ID'
        @generator = config[:generator] || -> { SecureRandom.uuid }
      end
      
      def call(request, response)
        request_id = request.headers["HTTP_#{header_to_env(@header_name)}"]
        request_id ||= @generator.call
        request.instance_variable_set(:@request_id, request_id)
        response.headers[@header_name] = request_id
        
        nil  # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
      
      private
      
      def header_to_env(header_name)
        # Convert X-Request-ID → X_REQUEST_ID
        header_name.upcase.gsub('-', '_')
      end
    end
  end
end

Aris.register_plugin(:request_id, plugin_class: Aris::Plugins::RequestId)