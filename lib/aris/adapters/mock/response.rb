# lib/aris/adapters/mock/response.rb
module Aris
  module Adapters
    module Mock
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
