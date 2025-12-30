# lib/aris/plugins/health_check.rb
module Aris
  module Plugins
    class HealthCheck
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @path = config[:path] || '/health'
        @checks = config[:checks] || {}
        @name = config[:name] || 'app'
        @version = config[:version]
      end
      
      def call(request, response)
        # Only handle health check path
        return nil unless request.path == @path
        
        # Run health checks
        results = {}
        overall_healthy = true
        
        @checks.each do |name, check_proc|
          begin
            check_result = check_proc.call
            results[name] = check_result ? 'ok' : 'fail'
            overall_healthy = false unless check_result
          rescue => e
            results[name] = "error: #{e.message}"
            overall_healthy = false
          end
        end
        
        # Build response
        health_data = {
          status: overall_healthy ? 'ok' : 'degraded',
          name: @name,
          checks: results
        }
        
        health_data[:version] = @version if @version
        health_data[:timestamp] = Time.now.iso8601
        
        # Set status code
        status = overall_healthy ? 200 : 503
        
        response.status = status
        response.headers['content-type'] = 'application/json'
        response.body = [health_data.to_json]
        
        response  # Halt pipeline
      end
      
      def self.build(**config)
        new(**config)
      end
    end
  end
end

# Self-register
Aris.register_plugin(:health_check, plugin_class: Aris::Plugins::HealthCheck)