# lib/aris/plugins/session.rb
require 'json'
require 'base64'
require 'openssl'

module Aris
  module Plugins
    class Session
      @default_config = {
        enabled: true,
        store: :cookie,
        key: '_aris_session',
        expire_after: 14 * 24 * 3600, # 2 weeks in seconds
        secret: nil
      }
      
      class << self
        attr_accessor :default_config
        
        def call(request, response)
          load_session(request)
          nil
        end
        
        def call_response(request, response)
          return unless request.respond_to?(:session)
          
          store_session(request, response)
        end
        
        def build(**config)
          config = default_config.merge(config)
          config[:secret] ||= Aris::Config.secret_key_base
          new(config)
        end
        
        private
        
        def load_session(request)
          session_data = load_from_store(request)
          
          request.define_singleton_method(:session) do
            @session ||= SessionData.new(session_data)
          end
        end
        
        def store_session(request, response)
          return unless request.session.changed? || request.session.destroyed?
          
          if request.session.destroyed?
            clear_from_store(request, response)
          else
            save_to_store(request, response, request.session.to_hash)
          end
        end
        
        def load_from_store(request)
          case default_config[:store]
          when :cookie
            load_from_cookie(request)
          else
            {} # Default empty session
          end
        end
        
        def save_to_store(request, response, data)
          case default_config[:store]
          when :cookie
            save_to_cookie(request, response, data)
          end
        end
        
        def clear_from_store(request, response)
          case default_config[:store]
          when :cookie
            clear_cookie(response)
          end
        end
        
        def load_from_cookie(request)
          return {} unless request.respond_to?(:cookies)
          
          cookie_value = request.cookies[default_config[:key]]
          return {} unless cookie_value
          
          begin
            # For encrypted sessions
            decrypt_session(cookie_value)
          rescue
            {} # Invalid session, start fresh
          end
        end
        
        def save_to_cookie(request, response, data)
          return if data.empty?
          
          encrypted_data = encrypt_session(data)
          response.set_cookie(default_config[:key], encrypted_data, {
            httponly: true,
            secure: (ENV['RACK_ENV'] == 'production'),
            path: '/',
            max_age: default_config[:expire_after]
          })
        end
        
        def clear_cookie(response)
          response.delete_cookie(default_config[:key])
        end
        
        def encrypt_session(data)
          # Simple encryption for demo - use proper encryption in production
          json_data = data.to_json
          Base64.urlsafe_encode64(json_data)
        end
        
        def decrypt_session(encrypted_data)
          json_data = Base64.urlsafe_decode64(encrypted_data)
          JSON.parse(json_data, symbolize_names: true)
        end
      end
      
      def initialize(config)
        @config = config
      end
      
      # Session data container
      class SessionData
        def initialize(initial_data = {})
          @data = initial_data || {}
          @changed = false
          @destroyed = false
        end
        
        def [](key)
          @data[key.to_sym]
        end
        
        def []=(key, value)
          @data[key.to_sym] = value
          @changed = true
        end
        
        def delete(key)
          @data.delete(key.to_sym)
          @changed = true
        end
        
        def clear
          @data.clear
          @changed = true
        end
        
        def destroy
          clear
          @destroyed = true
        end
        
        def to_hash
          @data.dup
        end
        
        def changed?
          @changed
        end
        
        def destroyed?
          @destroyed
        end
      end
    end
  end
end

# Register the plugin
Aris.register_plugin(:session, plugin_class: Aris::Plugins::Session)