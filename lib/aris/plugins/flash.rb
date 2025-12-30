# lib/aris/plugins/flash.rb - Complete rewrite of FlashData
require 'json'
require 'base64'
require 'set'

module Aris
  module Plugins
    class Flash
      def self.call(request, response)
        # Load flash data from cookie and initialize flash object
        flash_data = load_flash_from_cookie(request)
        
        # Define flash method on request
        request.define_singleton_method(:flash) do
          @flash ||= flash_data
        end
        
        nil # Continue pipeline
      end
      
      def self.call_response(request, response)
        return unless request.respond_to?(:flash)
        
        flash = request.flash
        data_to_store = flash.to_store
        
        if data_to_store.any?
          # Store flash for next request
          encoded = Base64.urlsafe_encode64(data_to_store.to_json)
          response.set_cookie('_aris_flash', encoded, {
            httponly: true,
            path: '/'
          })
        elsif request.cookies && request.cookies['_aris_flash']
          # Clear flash cookie if no data to store
          response.delete_cookie('_aris_flash')
        end
      end

      def self.build(**config)
        self
      end

      private

      def self.load_flash_from_cookie(request)
        return FlashData.new unless request.respond_to?(:cookies)
        
        cookie_value = request.cookies['_aris_flash']
        return FlashData.new unless cookie_value && !cookie_value.empty?
        
        begin
          decoded = Base64.urlsafe_decode64(cookie_value)
          data = JSON.parse(decoded, symbolize_names: true)
          FlashData.new(data)
        rescue StandardError
          # If cookie is invalid, start with empty flash
          FlashData.new
        end
      end

      # Internal flash data storage
# Alternative FlashData implementation with more explicit tracking
class FlashData
  def initialize(initial_data = {})
    @current = initial_data || {}
    @next = {}
    @now = {}
    # Use a simple array to track reads
    @read_keys = []
  end
  
  def [](key)
    key = key.to_sym
    
    # Check now first
    return @now[key] if @now.key?(key)
    
    # Check current
    if @current.key?(key) && !@read_keys.include?(key)
      value = @current[key]
      @read_keys << key
      return value
    end
    
    # Check next
    @next[key]
  end
  
  def []=(key, value)
    @next[key.to_sym] = value
  end
  
  def now
    FlashNow.new(@now)
  end
  
  def any?
    @current.any? || @next.any? || @now.any?
  end
  
  def to_store
    # Remove any keys that have been read
    unused_current = @current.reject { |k, _| @read_keys.include?(k) }
    unused_current.merge(@next)
  end
end
      # Flash.now proxy - only modifies current request data
      class FlashNow
        def initialize(now_data)
          @now_data = now_data
        end
        
        def [](key)
          @now_data[key.to_sym]
        end
        
        def []=(key, value)
          @now_data[key.to_sym] = value
        end
      end
    end
  end
end