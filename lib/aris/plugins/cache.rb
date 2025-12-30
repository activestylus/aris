# lib/aris/plugins/cache.rb
require 'digest'

module Aris
  module Plugins
    class Cache
      attr_reader :config
      
      def initialize(**config)
        @config = config
        @ttl = config[:ttl] || 60  # Default 1 minute
        @store = config[:store] || {}  # In-memory hash
        @mutex = Mutex.new
        @skip_paths = Array(config[:skip_paths] || [])
        @cache_control = config[:cache_control]
      end
      
      def call(request, response)
        # Only cache GET requests
        return nil unless request.method == 'GET'
        
        # Skip if path matches skip pattern
        return nil if @skip_paths.any? { |pattern| request.path.match?(pattern) }
        
        # Check if client sent Cache-Control: no-cache
        cache_control = request.headers['HTTP_CACHE_CONTROL']
        return nil if cache_control&.include?('no-cache')
        
        # Generate cache key
        cache_key = generate_cache_key(request)
        
        # Try to get from cache
        cached = get_from_cache(cache_key)
        if cached
          # Cache hit - restore response from cache
          response.status = cached[:status]
          response.headers.merge!(cached[:headers])
          response.body = cached[:body]
          response.headers['X-Cache'] = 'HIT'
          
          return response  # Halt pipeline
        end
        
        # Cache miss - store request info for response phase
        request.instance_variable_set(:@cache_key, cache_key)
        
        nil  # Continue to handler
      end
      
      # Response plugin - cache the result
      def call_response(request, response)
        # Only cache successful GET responses
        return unless request.method == 'GET'
        return unless response.status == 200
        
        cache_key = request.instance_variable_get(:@cache_key)
        return unless cache_key
        
        # Store in cache
        set_in_cache(cache_key, {
          status: response.status,
          headers: response.headers.dup,
          body: response.body.dup
        })
        
        # Add cache headers
        response.headers['X-Cache'] = 'MISS'
        if @cache_control
          response.headers['Cache-Control'] = @cache_control
        end
      end
      
      def self.build(**config)
        new(**config)
      end
      
      # For testing: clear cache
      def clear!
        @mutex.synchronize { @store.clear }
      end
      
      private
      
      def generate_cache_key(request)
        # Include domain, path, and query string
        key_string = "#{request.domain}:#{request.path}"
        key_string += "?#{request.query}" unless request.query.nil? || request.query.empty?
        
        Digest::MD5.hexdigest(key_string)
      end
      
      def get_from_cache(key)
        @mutex.synchronize do
          entry = @store[key]
          return nil unless entry
          
          # Check if expired
          if Time.now > entry[:expires_at]
            @store.delete(key)
            return nil
          end
          
          entry[:value]
        end
      end
      
      def set_in_cache(key, value)
        @mutex.synchronize do
          @store[key] = {
            value: value,
            expires_at: Time.now + @ttl
          }
        end
      end
    end
  end
end


Aris.register_plugin(:cache, plugin_class: Aris::Plugins::Cache)