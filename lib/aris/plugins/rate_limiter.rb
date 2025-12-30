module Aris
  module Plugins
    class RateLimiter
      LIMIT_WINDOW = 60
      
      # In-memory store (replace with Redis in production)
      @@store = {}
      @@mutex = Mutex.new
      
      def self.call(request, response)
        key = request.headers['HTTP_X_API_KEY'] || request.host
        
        if limit_exceeded?(key)
          response.status = 429
          response.headers['content-type'] = 'text/plain'
          response.headers['Retry-After'] = LIMIT_WINDOW.to_s
          response.body = ['Rate limit exceeded. Try again later.']
          return response # Halt pipeline
        end
        
        increment_count(key)
        nil # Continue pipeline
      end
      
      private
      
      def self.limit_exceeded?(key)
        @@mutex.synchronize do
          entry = @@store[key]
          return false unless entry
          
          # Check if we're still in the window and over limit
          entry[:count] >= 100 && (Time.now - entry[:window_start]) < LIMIT_WINDOW
        end
      end
      
      def self.increment_count(key)
        @@mutex.synchronize do
          entry = @@store[key] ||= { count: 0, window_start: Time.now }
          
          # Reset window if expired
          if (Time.now - entry[:window_start]) >= LIMIT_WINDOW
            entry[:count] = 0
            entry[:window_start] = Time.now
          end
          
          entry[:count] += 1
        end
      end
      
      # For testing: clear the store
      def self.reset!
        @@mutex.synchronize { @@store.clear }
      end
    end
  end
end

# Self-register
Aris.register_plugin(:rate_limit, plugin_class: Aris::Plugins::RateLimiter)