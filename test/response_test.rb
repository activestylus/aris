# test/response_helpers_test.rb
require 'minitest/autorun'
require 'json'
require 'tempfile'
require_relative '../lib/aris'

class ResponseHelpersTest < Minitest::Test
  def setup
    Aris::Router.send(:reset!)
    Aris.default(
      not_found: ->(req, params) { [404, {}, ['Not Found']] },
      error: ->(req, exc) { [500, {}, ["Error: #{exc.class}"]] }
    )
  end

  # Test JSON helper
  def test_json_helper
    Aris.routes({
      "example.com" => {
        "/api" => {
          get: {
            to: ->(req, res, params) {
              res.json({ message: "Hello", count: 42 })
            }
          }
        }
      }
    })

    response = call_route('/api')
    assert_equal 200, response[:status]
    assert_equal 'application/json', response[:headers]['content-type']
    assert_equal '{"message":"Hello","count":42}', response[:body].first
  end

  def test_json_helper_with_custom_status
    Aris.routes({
      "example.com" => {
        "/api" => {
          post: {
            to: ->(req, res, params) {
              res.json({ id: 123 }, status: 201)
            }
          }
        }
      }
    })

    response = call_route('/api', method: :post)
    assert_equal 201, response[:status]
    assert_equal '{"id":123}', response[:body].first
  end

  # Test HTML helper
  def test_html_helper
    Aris.routes({
      "example.com" => {
        "/page" => {
          get: {
            to: ->(req, res, params) {
              res.html("<h1>Welcome</h1><p>Test page</p>")
            }
          }
        }
      }
    })

    response = call_route('/page')
    assert_equal 200, response[:status]
    assert_equal 'text/html; charset=utf-8', response[:headers]['content-type']
    assert_equal "<h1>Welcome</h1><p>Test page</p>", response[:body].first
  end

  # Test text helper
  def test_text_helper
    Aris.routes({
      "example.com" => {
        "/ping" => {
          get: {
            to: ->(req, res, params) {
              res.text("pong")
            }
          }
        }
      }
    })

    response = call_route('/ping')
    assert_equal 200, response[:status]
    assert_equal 'text/plain; charset=utf-8', response[:headers]['content-type']
    assert_equal "pong", response[:body].first
  end

  # Test redirect helper
  def test_redirect_helper
    Aris.routes({
      "example.com" => {
        "/old" => {
          get: {
            to: ->(req, res, params) {
              res.redirect("/new")
            }
          }
        }
      }
    })

    response = call_route('/old')
    assert_equal 302, response[:status]
    assert_equal '/new', response[:headers]['location']
    assert_match(/Redirecting/, response[:body].first)
  end

  def test_redirect_helper_with_custom_status
    Aris.routes({
      "example.com" => {
        "/old" => {
          get: {
            to: ->(req, res, params) {
              res.redirect("/new-permanent", status: 301)
            }
          }
        }
      }
    })

    response = call_route('/old')
    assert_equal 301, response[:status]
    assert_equal '/new-permanent', response[:headers]['location']
  end

  # Test redirect_to helper with named routes
  def test_redirect_to_helper
    Aris.routes({
      "example.com" => {
        "/users/:id" => {
          get: {
            to: ->(req, res, params) { res.text("User #{params[:id]}") },
            as: :user
          }
        },
        "/go-to-user" => {
          get: {
            to: ->(req, res, params) {
              res.redirect_to(:user, id: 456)
            }
          }
        }
      }
    })

    response = call_route('/go-to-user')
    assert_equal 302, response[:status]
    assert_equal '/users/456', response[:headers]['location']
  end

  # Test no_content helper
  def test_no_content_helper
    Aris.routes({
      "example.com" => {
        "/empty" => {
          delete: {
            to: ->(req, res, params) {
              res.no_content
            }
          }
        }
      }
    })

    response = call_route('/empty', method: :delete)
    assert_equal 204, response[:status]
    assert_empty response[:body]
    refute response[:headers].key?('content-type')
  end

  # Test XML helper
  def test_xml_helper
    Aris.routes({
      "example.com" => {
        "/feed" => {
          get: {
            to: ->(req, res, params) {
              res.xml("<rss><channel><title>Test</title></channel></rss>")
            }
          }
        }
      }
    })

    response = call_route('/feed')
    assert_equal 200, response[:status]
    assert_equal 'application/xml; charset=utf-8', response[:headers]['content-type']
    assert_equal "<rss><channel><title>Test</title></channel></rss>", response[:body].first
  end

  # Test send_file helper
  def test_send_file_helper
    file = Tempfile.new(['test', '.txt'])
    file.write('File content for testing')
    file.close

    Aris.routes({
      "example.com" => {
        "/download" => {
          get: {
            to: ->(req, res, params) {
              res.send_file(file.path)
            }
          }
        }
      }
    })

    response = call_route('/download')
    assert_equal 200, response[:status]
    assert_equal 'text/plain', response[:headers]['content-type']
    assert_match(/attachment/, response[:headers]['content-disposition'])
    assert_equal 'File content for testing', response[:body].first

  ensure
    file.unlink if file
  end

  def test_send_file_with_custom_filename
    file = Tempfile.new(['test', '.txt'])
    file.write('Content')
    file.close

    Aris.routes({
      "example.com" => {
        "/download" => {
          get: {
            to: ->(req, res, params) {
              res.send_file(file.path, filename: 'custom-name.txt')
            }
          }
        }
      }
    })

    response = call_route('/download')
    assert_match(/custom-name\.txt/, response[:headers]['content-disposition'])

  ensure
    file.unlink if file
  end

  def test_send_file_with_custom_type
    file = Tempfile.new(['test', '.bin'])
    file.write('Binary data')
    file.close

    Aris.routes({
      "example.com" => {
        "/download" => {
          get: {
            to: ->(req, res, params) {
              res.send_file(file.path, type: 'application/octet-stream')
            }
          }
        }
      }
    })

    response = call_route('/download')
    assert_equal 'application/octet-stream', response[:headers]['content-type']

  ensure
    file.unlink if file
  end

  def test_send_file_with_inline_disposition
    file = Tempfile.new(['test', '.pdf'])
    file.write('PDF content')
    file.close

    Aris.routes({
      "example.com" => {
        "/view" => {
          get: {
            to: ->(req, res, params) {
              res.send_file(file.path, disposition: 'inline')
            }
          }
        }
      }
    })

    response = call_route('/view')
    assert_match(/inline/, response[:headers]['content-disposition'])

  ensure
    file.unlink if file
  end

  # Test method chaining (fluent interface)
  def test_helper_methods_are_chainable
    Aris.routes({
      "example.com" => {
        "/test" => {
          get: {
            to: ->(req, res, params) {
              # All helpers should return the response object
              result = res.json({ test: true })
              assert_same res, result
              result
            }
          }
        }
      }
    })

    response = call_route('/test')
    assert_equal 200, response[:status]
  end

  # Test error handling in send_file
  def test_send_file_with_missing_file
    Aris.routes({
      "example.com" => {
        "/missing" => {
          get: {
            to: ->(req, res, params) {
              res.send_file('/nonexistent/file.txt')
            }
          }
        }
      }
    })

    response = call_route('/missing')
    assert_equal 500, response[:status]
    assert_match(/Error: ArgumentError/, response[:body].first)
  end

  # Test early return with helpers
  def test_early_return_with_helpers
    Aris.routes({
      "example.com" => {
        "/check" => {
          get: {
            to: ->(req, res, params) {
              if req.query == 'fail=true'
                return res.json({ error: "Failed" }, status: 400)
              end
              res.json({ success: true })
            }
          }
        }
      }
    })

    # Test early return case
    error_response = call_route('/check', query: 'fail=true')
    assert_equal 400, error_response[:status]
    assert_equal '{"error":"Failed"}', error_response[:body].first

    # Test normal case
    success_response = call_route('/check')
    assert_equal 200, success_response[:status]
    assert_equal '{"success":true}', success_response[:body].first
  end

  # Test MIME type detection in send_file
  def test_send_file_mime_type_detection
    extensions = {
      '.pdf' => 'application/pdf',
      '.jpg' => 'image/jpeg',
      '.json' => 'application/json',
      '.html' => 'text/html'
    }

    extensions.each do |ext, expected_type|
      file = Tempfile.new(['test', ext])
      file.write('content')
      file.close

      Aris.routes({
        "example.com" => {
          "/file" => {
            get: {
              to: ->(req, res, params) {
                res.send_file(file.path)
              }
            }
          }
        }
      })

      response = call_route('/file')
      assert_equal expected_type, response[:headers]['content-type']

      file.unlink
      Aris::Router.send(:reset!)
    end
  end
def test_negotiate_helper_with_format_symbols
  Aris.routes({
    "example.com" => {
      "/user/:id" => {
        get: {
          to: ->(req, res, params) {
            user_data = { id: params[:id], name: "User #{params[:id]}" }
            
            res.negotiate(:json) do |format|
              case format
              when :json then user_data
              when :xml then "<user><id>#{user_data[:id]}</id></user>"
              when :html then "<div>User #{user_data[:id]}</div>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/user/123')
  assert_equal 200, response[:status]
  assert_equal 'application/json', response[:headers]['content-type']
  assert_equal '{"id":"123","name":"User 123"}', response[:body].first
end

def test_negotiate_helper_with_mime_types
  Aris.routes({
    "example.com" => {
      "/user/:id" => {
        get: {
          to: ->(req, res, params) {
            user_data = { id: params[:id], name: "User #{params[:id]}" }
            
            res.negotiate('application/xml') do |format|
              case format
              when :json then user_data
              when :xml then "<user><id>#{user_data[:id]}</id></user>"
              when :html then "<div>User #{user_data[:id]}</div>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/user/456')
  assert_equal 200, response[:status]
  assert_equal 'application/xml; charset=utf-8', response[:headers]['content-type']
  assert_equal '<user><id>456</id></user>', response[:body].first
end

def test_negotiate_helper_with_html
  Aris.routes({
    "example.com" => {
      "/user/:id" => {
        get: {
          to: ->(req, res, params) {
            user_data = { id: params[:id], name: "User #{params[:id]}" }
            
            res.negotiate('text/html') do |format|
              case format
              when :json then user_data
              when :xml then "<user><id>#{user_data[:id]}</id></user>"
              when :html then "<div class='user'>#{user_data[:name]}</div>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/user/789')
  assert_equal 200, response[:status]
  assert_equal 'text/html; charset=utf-8', response[:headers]['content-type']
  assert_equal "<div class='user'>User 789</div>", response[:body].first
end

def test_negotiate_helper_defaults_to_json
  Aris.routes({
    "example.com" => {
      "/user/:id" => {
        get: {
          to: ->(req, res, params) {
            user_data = { id: params[:id], name: "User #{params[:id]}" }
            
            res.negotiate('unknown/format') do |format|
              case format
              when :json then user_data
              when :xml then "<user><id>#{user_data[:id]}</id></user>"
              when :html then "<div>User #{user_data[:id]}</div>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/user/999')
  assert_equal 200, response[:status]
  assert_equal 'application/json', response[:headers]['content-type']
  assert_equal '{"id":"999","name":"User 999"}', response[:body].first
end

def test_negotiate_helper_with_custom_data_structures
  Aris.routes({
    "example.com" => {
      "/data" => {
        get: {
          to: ->(req, res, params) {
            data = { items: [1, 2, 3], total: 3 }
            
            res.negotiate(:xml) do |format|
              case format
              when :json 
                data
              when :xml
                items_xml = data[:items].map { |i| "<item>#{i}</item>" }.join
                "<data><items>#{items_xml}</items><total>#{data[:total]}</total></data>"
              when :html
                items_list = data[:items].map { |i| "<li>#{i}</li>" }.join
                "<ul>#{items_list}</ul><p>Total: #{data[:total]}</p>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/data')
  assert_equal 200, response[:status]
  assert_equal 'application/xml; charset=utf-8', response[:headers]['content-type']
  assert_equal '<data><items><item>1</item><item>2</item><item>3</item></items><total>3</total></data>', response[:body].first
end

def test_negotiate_helper_preserves_status_codes
  Aris.routes({
    "example.com" => {
      "/not-found" => {
        get: {
          to: ->(req, res, params) {
            res.negotiate(:json, status: 404) do |format|
              case format
              when :json then { error: "Not found" }
              when :xml then "<error>Not found</error>"
              when :html then "<h1>404 Not Found</h1>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/not-found')
  assert_equal 404, response[:status]
  assert_equal 'application/json', response[:headers]['content-type']
  assert_equal '{"error":"Not found"}', response[:body].first
end

def test_negotiate_helper_with_empty_block
  Aris.routes({
    "example.com" => {
      "/empty" => {
        get: {
          to: ->(req, res, params) {
            res.negotiate(:json) do |format|
              # Block returns nil
            end
          }
        }
      }
    }
  })

  response = call_route('/empty')
  assert_equal 200, response[:status]
  assert_equal 'application/json', response[:headers]['content-type']
  assert_equal '{}', response[:body].first # nil becomes empty hash
end

def test_negotiate_helper_with_pre_encoded_json
  Aris.routes({
    "example.com" => {
      "/pre-encoded" => {
        get: {
          to: ->(req, res, params) {
            res.negotiate(:json) do |format|
              case format
              when :json then '{"pre":"encoded","value":42}'
              when :xml then "<data><pre>encoded</pre></data>"
              when :html then "<div>Pre-encoded</div>"
              end
            end
          }
        }
      }
    }
  })

  response = call_route('/pre-encoded')
  assert_equal 200, response[:status]
  assert_equal 'application/json', response[:headers]['content-type']
  assert_equal '{"pre":"encoded","value":42}', response[:body].first
end
  private

  def call_route(path, method: :get, domain: 'example.com', query: '')
    adapter = Aris::Adapters::Mock::Adapter.new
    adapter.call(method: method, path: path, domain: domain, query: query)
  end
end