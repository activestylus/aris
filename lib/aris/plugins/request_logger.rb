# lib/aris/plugins/request_logger.rb
require 'json'
require 'logger'

module Aris
  module Plugins
    class RequestLogger
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @format = config[:format] || :text
        @exclude = Array(config[:exclude] || [])
        @logger = config[:logger] || ::Logger.new(STDOUT)
      end
      
      def call(request, response)
        # Skip excluded paths
        return nil if @exclude.include?(request.path)
        
        # Log the request
        entry = {
          method: request.method,
          path: request.path,
          host: request.host,
          timestamp: Time.now.iso8601
        }
        
        if @format == :json
          @logger.info(JSON.generate(entry))
        else
          @logger.info("#{entry[:method]} #{entry[:path]}")
        end
        
        nil  # Continue pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
    end
  end
end