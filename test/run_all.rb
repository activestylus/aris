Dir[File.join(__dir__, '*.rb')].each { |file| require_relative file }

%w(utils plugins adapters).map do |f|
  Dir[File.join(__dir__, f, '**', '*.rb')].each { |file| require_relative file }
end

