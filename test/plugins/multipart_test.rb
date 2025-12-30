# test/plugins/multipart_test.rb
require_relative '../test_helper'

class MultipartHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    if data
      files = data.select { |p| p[:type] == :file }
      fields = data.select { |p| p[:type] == :field }
      
      {
        files: files.map { |f| { name: f[:name], filename: f[:filename], size: f[:data].bytesize } },
        fields: fields.map { |f| { name: f[:name], value: f[:data] } }
      }
    else
      { error: "No multipart data" }
    end
  end
end

class MultipartTest < Minitest::Test
  def setup
    Aris::Router.default_domain = "example.com"
    @app = Aris::Adapters::Mock::Adapter.new
  end
  
  def teardown
    Thread.current[:aris_current_domain] = nil
  end
  
  def build_multipart_body(boundary, parts)
    body = ""
    parts.each do |part|
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"#{part[:name]}\""
      body << "; filename=\"#{part[:filename]}\"" if part[:filename]
      body << "\r\n"
      body << "content-type: #{part[:content_type]}\r\n" if part[:content_type]
      body << "\r\n"
      body << part[:data]
      body << "\r\n"
    end
    body << "--#{boundary}--\r\n"
    body
  end
  
  def build_env(path, body:, boundary:)
    {
      method: 'POST',
      path: path,
      domain: 'example.com',
      headers: {
        'CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}"
      },
      body: body
    }
  end
  
  # Test: Parse single file upload
  def test_single_file_upload
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundary123"
    body = build_multipart_body(boundary, [
      {
        name: 'file',
        filename: 'test.txt',
        content_type: 'text/plain',
        data: 'Hello, World!'
      }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 1, response['files'].size
    assert_equal 'file', response['files'][0]['name']
    assert_equal 'test.txt', response['files'][0]['filename']
    assert_equal 13, response['files'][0]['size']
  end
  
  # Test: Parse multiple files
  def test_multiple_files
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundary456"
    body = build_multipart_body(boundary, [
      {
        name: 'file1',
        filename: 'test1.txt',
        content_type: 'text/plain',
        data: 'File 1'
      },
      {
        name: 'file2',
        filename: 'test2.txt',
        content_type: 'text/plain',
        data: 'File 2'
      }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 2, response['files'].size
  end
  
  # Test: Parse form fields
  def test_form_fields
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundary789"
    body = build_multipart_body(boundary, [
      { name: 'username', data: 'alice' },
      { name: 'email', data: 'alice@example.com' }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 2, response['fields'].size
    assert_equal 'username', response['fields'][0]['name']
    assert_equal 'alice', response['fields'][0]['value']
  end
  
  # Test: Mixed files and fields
  def test_mixed_files_and_fields
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundaryABC"
    body = build_multipart_body(boundary, [
      { name: 'title', data: 'My Upload' },
      {
        name: 'document',
        filename: 'doc.pdf',
        content_type: 'application/pdf',
        data: 'PDF content here'
      }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 200, result[:status]
    response = JSON.parse(result[:body].first)
    assert_equal 1, response['files'].size
    assert_equal 1, response['fields'].size
  end
  
  # Test: File size limit exceeded
  def test_file_size_limit
    multipart = Aris::Plugins::Multipart.build(max_file_size: 100)
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundaryDEF"
    body = build_multipart_body(boundary, [
      {
        name: 'file',
        filename: 'large.txt',
        content_type: 'text/plain',
        data: 'x' * 200  # 200 bytes, exceeds 100 limit
      }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 413, result[:status]
    assert_match /exceeds maximum size/, result[:body].first
  end
  
  # Test: Too many files
  def test_max_files_limit
    multipart = Aris::Plugins::Multipart.build(max_files: 2)
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundaryGHI"
    body = build_multipart_body(boundary, [
      { name: 'file1', filename: 'test1.txt', data: 'File 1' },
      { name: 'file2', filename: 'test2.txt', data: 'File 2' },
      { name: 'file3', filename: 'test3.txt', data: 'File 3' }
    ])
    
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    
    assert_equal 413, result[:status]
    assert_match /Too many files/, result[:body].first
  end
  
  # Test: Allowed extensions
  def test_allowed_extensions
    multipart = Aris::Plugins::Multipart.build(
      allowed_extensions: ['.txt', '.pdf']
    )
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundaryJKL"
    
    # Valid extension
    body = build_multipart_body(boundary, [
      { name: 'file', filename: 'test.txt', data: 'OK' }
    ])
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    assert_equal 200, result[:status]
    
    # Invalid extension
    body = build_multipart_body(boundary, [
      { name: 'file', filename: 'test.exe', data: 'NOT OK' }
    ])
    result = @app.call(**build_env('/upload', body: body, boundary: boundary))
    assert_equal 400, result[:status]
    assert_match /not allowed/, result[:body].first
  end
  
  # Test: Missing boundary
  def test_missing_boundary
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { post: { to: MultipartHandler } }
      }
    })
    
    result = @app.call(
      method: 'POST',
      path: '/upload',
      domain: 'example.com',
      headers: { 'CONTENT_TYPE' => 'multipart/form-data' },  # No boundary
      body: 'some data'
    )
    
    assert_equal 400, result[:status]
    assert_match /Missing boundary/, result[:body].first
  end
  
  # Test: Only POST/PUT/PATCH methods
  def test_only_parseable_methods
    multipart = Aris::Plugins::Multipart.build
    
    Aris.routes({
      "example.com": {
        use: [multipart],
        "/upload": { get: { to: MultipartHandler } }
      }
    })
    
    boundary = "----WebKitFormBoundaryMNO"
    body = build_multipart_body(boundary, [
      { name: 'file', filename: 'test.txt', data: 'data' }
    ])
    
    result = @app.call(
      method: 'GET',
      path: '/upload',
      domain: 'example.com',
      headers: { 'CONTENT_TYPE' => "multipart/form-data; boundary=#{boundary}" },
      body: body
    )
    
    # Should not parse (GET not in PARSEABLE_METHODS)
    response = JSON.parse(result[:body].first)
    assert_equal 'No multipart data', response['error']
  end
end