# lib/aris.rb
# Main Aris loader - requires all components in correct order

# Core functionality
require_relative 'aris/core'
require_relative 'aris/pipeline_runner'
require_relative 'aris/locale_injector'
require_relative 'aris/route_helpers'
require_relative 'aris/response_helpers'
require_relative 'aris/discovery'
require_relative 'aris/plugins'

# Adapters
require_relative 'aris/adapters/base'
require_relative 'aris/adapters/joys_integration'
require_relative 'aris/adapters/rack/response'
require_relative 'aris/adapters/rack/request'
require_relative 'aris/adapters/rack/adapter'
require_relative 'aris/adapters/mock/response'
require_relative 'aris/adapters/mock/request'
require_relative 'aris/adapters/mock/adapter'

# Utils (if available)
begin
  require_relative 'aris/utils/sitemap'
  require_relative 'aris/utils/redirects'
rescue LoadError
  # Utils not available, that's ok
end

# Plugins (optional)
Dir[File.join(__dir__, 'aris/plugins/**/*.rb')].sort.each do |file|
  require file
end