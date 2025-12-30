# aris.gemspec
require_relative "lib/aris/version"

Gem::Specification.new do |spec|
  spec.name          = "aris"
  spec.version       = Aris::VERSION
  spec.authors       = ["Steven Garcia"]
  spec.email         = ["stevendgarcia@gmail.com"]
  
  spec.summary       = "Fast, elegant Ruby web framework"
  spec.description   = "Aris is a lightweight, high-performance web framework for Ruby with powerful routing, middleware pipeline, and seamless integrations."
  spec.homepage      = "https://github.com/activestylus/aris"
  spec.license       = "MIT"
  
  spec.required_ruby_version = ">= 3.0.0"
  
  spec.files         = Dir["lib/**/*", "README.md", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  
  # Dependencies
  spec.add_dependency "rack", "~> 3.0"
  
  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "benchmark-ips", "~> 2.0" 
  spec.add_development_dependency "benchmark-memory", "~> 0.2"
end