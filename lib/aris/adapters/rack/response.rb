# lib/aris/adapters/rack/response.rb
module Aris
  module Adapters
    module Rack
      class Response
        include Aris::ResponseHelpers
        attr_accessor :status, :headers, :body
        def initialize
          @status = 200
          @headers = {'content-type' => 'text/html'}
          @body = []
        end
      end
    end
  end
end