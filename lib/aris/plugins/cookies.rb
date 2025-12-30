# lib/aris/plugins/cookies.rb
module Aris
  module Plugins
    class Cookies
      def self.call(request, response)
        # Only add cookie helpers when plugin is used
        add_cookie_helpers(request, response)
        nil # Continue pipeline
      end

      def self.build(**config)
        self
      end

      private

      def self.add_cookie_helpers(request, response)
        # Add cookie writing methods to response
        response.define_singleton_method(:set_cookie) do |name, value, options = {}|
          default_options = Aris::Config.cookie_options || {}
          merged_options = default_options.merge(options)
          
          cookie_parts = ["#{name}=#{value}"]
          cookie_parts << "Path=#{merged_options[:path]}" if merged_options[:path]
          cookie_parts << "HttpOnly" if merged_options[:httponly]
          cookie_parts << "Secure" if merged_options[:secure]
          cookie_parts << "Max-Age=#{merged_options[:max_age]}" if merged_options[:max_age]
          cookie_parts << "SameSite=#{merged_options[:same_site]}" if merged_options[:same_site]
          
          cookie_string = cookie_parts.join("; ")
          
          if headers['Set-Cookie']
            headers['Set-Cookie'] = [headers['Set-Cookie'], cookie_string].join(", ")
          else
            headers['Set-Cookie'] = cookie_string
          end
        end

        response.define_singleton_method(:delete_cookie) do |name, options = {}|
          set_cookie(name, "", options.merge(max_age: 0))
        end
      end
    end
  end
end
Aris.register_plugin(:cookies, plugin_class: Aris::Plugins::Cookies)