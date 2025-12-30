module Aris
  module Plugins
    @@registry = {}
    
    def self.register(name, *classes)
      raise ArgumentError, "Plugin '#{name}' requires at least one class" if classes.empty?
      @@registry[name.to_sym] = classes.flatten
    end
    
    def self.resolve(name)
      @@registry[name.to_sym] || raise(ArgumentError, "Unknown plugin :#{name}")
    end
  end
  
  def self.register_plugin(name, **options)
    classes = [options[:generator], options[:protection], options[:plugin_class]].flatten.compact
    Plugins.register(name, *classes)
  end
  
  def self.resolve_plugin(name)
    Plugins.resolve(name)
  end
end