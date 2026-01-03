# lib/aris/adapters/base.rb
module Aris
  module Adapters
    class Base
      def handle_sitemap(request)
        return nil unless defined?(Aris::Utils::Sitemap) && request.path == '/sitemap.xml'
        
        xml = Aris::Utils::Sitemap.generate(
          base_url: "#{request.scheme}://#{request.host}",
          domain: request.host
        )
        [200, {'content-type' => 'application/xml'}, [xml]]
      end
      
      def handle_redirect(request)
        return nil unless defined?(Aris::Utils::Redirects)
        
        redirect = Aris::Utils::Redirects.find(request.path)
        return nil unless redirect
        
        [redirect[:status], {'location' => redirect[:to]}, []]
      end
    end
  end
end