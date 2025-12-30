require_relative 'base'

class JoysPlugin
  def initialize(app)
    @app = app
  end
  def call(env)
    request = Rack::Request.new(env)
    Thread.current[:joys_request] = request
    Thread.current[:joys_params] = {} 
    
    begin
      @app.call(env)
    ensure
      # Comprehensive cleanup
      Thread.current[:joys_request] = nil
      Thread.current[:joys_params]  = nil
      Thread.current[:joys_locals]  = nil
    end
  end
end

module Joys
  module Adapters
    class Aris < ::Aris::Adapters::Base
      def integrate!
        inject_helpers!
        [::Aris::Adapters::Mock::Response, ::Aris::Adapters::Rack::Response].each do |klass|
          klass.include(Renderer)
        end
      end

      def inject_helpers!
        Joys::Render::Helpers.module_eval do
          def request; Thread.current[:joys_request]; end
          def params;  Thread.current[:joys_params];  end
          def _(content); raw(content); end
          def path(route_name, **params)
            ::Aris.path(route_name, **params)  # Call on ::Aris module, not the adapter
          end
          def make(name, *args, **kwargs, &block)
            Joys.define :comp, name, *args, **kwargs, &block
          end 
          def load_css_file(*names)
			      names.each do |name|
			        file_path = File.join(Joys::Config.css_parts, "#{name}.css")
			        if File.exist?(file_path)
			          raw File.read(file_path)
			        else
			          raise "CSS file not found: #{file_path}"
			        end
			      end
			      nil
			    end
        end
      end


module Renderer
  def render(path, **locals)
    Thread.current[:joys_params] = locals[:params] || {}
    file = File.join(Joys::Config.pages, "#{path}.rb")
    raise "Template not found: #{file}" unless File.exist?(file)
    
    renderer = Object.new
    renderer.extend(Joys::Render::Helpers)
    renderer.extend(Joys::Tags)
    
    # Set the page name for style compilation
    page_name = "page_#{path.gsub('/', '_')}"
    
    # Initialize ALL Joys state on the renderer instance
    renderer.instance_variable_set(:@bf, String.new(capacity: 16384))
    renderer.instance_variable_set(:@slots, {})
    renderer.instance_variable_set(:@styles, [])
    renderer.instance_variable_set(:@style_base_css, [])
    renderer.instance_variable_set(:@style_media_queries, {})
    renderer.instance_variable_set(:@used_components, Set.new)
    renderer.instance_variable_set(:@current_page, page_name)  # ADD THIS!
    
    # Inject locals as methods
    locals.each { |k, v| renderer.define_singleton_method(k) { v } }
    
    # Evaluate the page file
    renderer.instance_eval(File.read(file), file)
    
    # Set the HTML on the Aris response
    self.html(renderer.instance_variable_get(:@bf))
    self
  end
end
    end
  end
end