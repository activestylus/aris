module Aris
  module PipelineRunner
    extend self
    
    def call(request:, route:, response:)

  if route[:subdomain]
    request.define_singleton_method(:subdomain) { route[:subdomain] }
    route[:params] ||= {}
    route[:params][:subdomain] = route[:subdomain]
  end
      if route[:use] && !route[:use].empty?
        route[:use].each do |plugin|
          result = plugin.call(request, response)
          if result.is_a?(Array) || (result.respond_to?(:status) && result.respond_to?(:headers) && result.respond_to?(:body))
            return result  # Plugin halted pipeline
          end
        end
      end

      handler = route[:handler]
      params = route[:params]
      result = execute_handler(handler, request, params, response)
      result = format_handler_result(result, response)
      
      if route[:use] && !route[:use].empty?
        route[:use].each do |plugin|
          if plugin.respond_to?(:call_response)
            plugin.call_response(request, result)
          end
        end
      end
      
      result
    end
    
    private
    
    def execute_handler(handler, request, params, response)
      case handler
      when Proc, Method
        if handler.parameters.length >= 3
          handler.call(request, response, params)
        else
          handler.call(request, params)
        end
      when String
        controller_name, action = handler.split('#')
        controller_class = Object.const_get(controller_name)
        controller = controller_class.new
        controller.send(action, request, params)
      else
        if handler.respond_to?(:call)
          method_obj = handler.method(:call)
          if method_obj.parameters.length >= 3
            handler.call(request, response, params)
          else
            handler.call(request, params)
          end
        else
          raise ArgumentError, "Handler doesn't respond to call: #{handler.inspect}"
        end
      end
    end
    
    def format_handler_result(result, response)
      case result
      when Array
        # Rack array [status, headers, body] - convert to response object
        response.status = result[0]
        response.headers.merge!(result[1])
        response.body = result[2]
        response
      when Hash
        # JSON response
        response.status = 200
        response.headers['content-type'] = 'application/json'
        response.body = [result.to_json]
        response
      when String
        # Plain text response
        response.status = 200
        response.headers['content-type'] = 'text/plain'
        response.body = [result]
        response
      else
        # Already a response object (or response-like)
        if result.respond_to?(:status) && result.respond_to?(:headers) && result.respond_to?(:body)
          result
        else
          # Treat as string
          response.status = 200
          response.headers['content-type'] = 'text/plain'
          response.body = [result.to_s]
          response
        end
      end
    end
  end
end