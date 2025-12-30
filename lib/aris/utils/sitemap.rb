# lib/aris/utils/sitemap.rb
module Aris
  module Utils
    module Sitemap
      class << self
        attr_reader :routes
        
        def reset!
          @routes = []
        end
        
        def register(domain:, path:, method:, metadata:)
          @routes ||= []
          @routes << {
            domain: domain,
            path: path,
            method: method,
            metadata: metadata
          }
        end
        
        def generate(base_url:, domain: nil)
          xml = ['<?xml version="1.0" encoding="UTF-8"?>']
          xml << '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
          
          sitemap_routes(domain).each do |route|
            route[:urls].each do |url_data|
              xml << '  <url>'
              xml << "    <loc>#{base_url}#{url_data[:path]}</loc>"
              xml << "    <lastmod>#{url_data[:lastmod]}</lastmod>" if url_data[:lastmod]
              xml << "    <changefreq>#{url_data[:changefreq]}</changefreq>"
              xml << "    <priority>#{url_data[:priority]}</priority>"
              xml << '  </url>'
            end
          end
          
          xml << '</urlset>'
          xml.join("\n")
        end
        
        private
        
        def sitemap_routes(domain_filter = nil)
          (@routes || []).select { |r| 
            r[:metadata] && (domain_filter.nil? || r[:domain] == domain_filter)
          }.map { |route|
            urls = if route[:metadata][:dynamic]
              route[:metadata][:dynamic].call
            else
              [{
                path: route[:path],
                priority: route[:metadata][:priority] || 0.5,
                changefreq: route[:metadata][:changefreq] || 'monthly',
                lastmod: route[:metadata][:lastmod]
              }]
            end
            
            route.merge(urls: urls)
          }.sort_by { |r| -(r[:urls].first[:priority] rescue 0.5) }
        end
      end
      
      reset!
    end
  end
end

# Extend RouteHelpers
module Aris
	module RouteHelpers
  def sitemap(priority: 0.5, changefreq: 'monthly', lastmod: nil, &dynamic)
    @_sitemap_metadata = {
      priority: priority,
      changefreq: changefreq,
      lastmod: lastmod,
      dynamic: dynamic
    }
  end
  
  def sitemap_metadata
    @_sitemap_metadata
  end
  end
end