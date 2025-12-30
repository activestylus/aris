# Multipart Parser Plugin (File Uploads)

Parses `multipart/form-data` requests for file uploads and form submissions. Essential for handling file uploads in web applications.

## Installation

```ruby
require 'aris/plugins/multipart'
```

## Basic Usage

```ruby
multipart = Aris::Plugins::Multipart.build

Aris.routes({
  "api.example.com": {
    use: [multipart],
    "/upload": { post: { to: UploadHandler } }
  }
})
```

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_file_size` | Integer | `10485760` (10MB) | Maximum file size in bytes |
| `max_files` | Integer | `10` | Maximum number of files per request |
| `allowed_extensions` | Array | `nil` (all allowed) | Whitelist of allowed file extensions (e.g., `['.jpg', '.png']`) |

## Examples

### Basic File Upload

```ruby
class UploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    
    files = data.select { |p| p[:type] == :file }
    file = files.first
    
    {
      message: "Uploaded #{file[:filename]}",
      size: file[:data].bytesize,
      type: file[:content_type]
    }
  end
end

multipart = Aris::Plugins::Multipart.build

Aris.routes({
  "api.example.com": {
    use: [multipart],
    "/upload": { post: { to: UploadHandler } }
  }
})
```

### Custom File Size Limit

```ruby
multipart = Aris::Plugins::Multipart.build(
  max_file_size: 5_242_880  # 5MB
)
```

### Restrict File Types

```ruby
multipart = Aris::Plugins::Multipart.build(
  allowed_extensions: ['.jpg', '.jpeg', '.png', '.gif']
)

# Only image files allowed
```

### Multiple Files with Limits

```ruby
multipart = Aris::Plugins::Multipart.build(
  max_files: 5,
  max_file_size: 2_097_152  # 2MB per file
)
```

### Processing Uploaded Files

```ruby
class ImageUploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    
    # Get all uploaded files
    files = data.select { |p| p[:type] == :file }
    
    # Get form fields
    fields = data.select { |p| p[:type] == :field }
    title = fields.find { |f| f[:name] == 'title' }&.dig(:data)
    
    # Process each file
    uploaded_files = files.map do |file|
      # Save to S3, disk, etc.
      save_file(file[:filename], file[:data])
      
      {
        name: file[:filename],
        size: file[:data].bytesize,
        content_type: file[:content_type]
      }
    end
    
    { title: title, files: uploaded_files }
  end
  
  def self.save_file(filename, data)
    # Save to disk, S3, etc.
    File.write("/tmp/uploads/#{filename}", data)
  end
end
```

### Mixed Form Data and Files

```ruby
class FormHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    
    # Extract files
    files = data.select { |p| p[:type] == :file }
    avatar = files.find { |f| f[:name] == 'avatar' }
    
    # Extract form fields
    fields = data.select { |p| p[:type] == :field }
    username = fields.find { |f| f[:name] == 'username' }&.dig(:data)
    email = fields.find { |f| f[:name] == 'email' }&.dig(:data)
    
    {
      user: { username: username, email: email },
      avatar: avatar ? { filename: avatar[:filename], size: avatar[:data].bytesize } : nil
    }
  end
end
```

## Parsed Data Structure

Multipart data is attached to request as `@multipart_data` array:

```ruby
[
  {
    name: 'avatar',               # Form field name
    filename: 'photo.jpg',        # Original filename
    content_type: 'image/jpeg',   # MIME type
    data: '...',                  # Binary file data
    type: :file                   # :file or :field
  },
  {
    name: 'username',
    data: 'alice',
    type: :field
  }
]
```

## Production Tips

### 1. File Size Limits by Type

```ruby
# Images
image_multipart = Aris::Plugins::Multipart.build(
  max_file_size: 5_242_880,  # 5MB
  allowed_extensions: ['.jpg', '.png', '.gif']
)

# Documents
doc_multipart = Aris::Plugins::Multipart.build(
  max_file_size: 10_485_760,  # 10MB
  allowed_extensions: ['.pdf', '.doc', '.docx']
)

Aris.routes({
  "api.example.com": {
    "/upload/image": { use: [image_multipart], post: { to: ImageHandler } },
    "/upload/document": { use: [doc_multipart], post: { to: DocHandler } }
  }
})
```

### 2. Save to Disk (Production)

Don't keep files in memory:

```ruby
class ProductionUploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    saved_files = files.map do |file|
      # Generate unique filename
      ext = File.extname(file[:filename])
      unique_name = "#{SecureRandom.uuid}#{ext}"
      path = "/var/uploads/#{unique_name}"
      
      # Write to disk
      File.binwrite(path, file[:data])
      
      {
        original_name: file[:filename],
        stored_path: path,
        size: file[:data].bytesize
      }
    end
    
    { files: saved_files }
  end
end
```

### 3. Upload to S3

```ruby
require 'aws-sdk-s3'

class S3UploadHandler
  S3_CLIENT = Aws::S3::Client.new(region: 'us-east-1')
  BUCKET = 'my-uploads-bucket'
  
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    uploaded_files = files.map do |file|
      key = "uploads/#{SecureRandom.uuid}/#{file[:filename]}"
      
      S3_CLIENT.put_object(
        bucket: BUCKET,
        key: key,
        body: file[:data],
        content_type: file[:content_type]
      )
      
      {
        filename: file[:filename],
        url: "https://#{BUCKET}.s3.amazonaws.com/#{key}",
        size: file[:data].bytesize
      }
    end
    
    { files: uploaded_files }
  end
end
```

### 4. Validate Content Type

Don't trust filename extensions:

```ruby
class SecureUploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    files.each do |file|
      # Check magic bytes (first few bytes)
      magic = file[:data][0..3]
      
      case magic
      when "\xFF\xD8\xFF"  # JPEG
        # Valid
      when "\x89PNG"       # PNG
        # Valid
      else
        return { error: "Invalid file type for #{file[:filename]}" }
      end
    end
    
    # Process files...
  end
end
```

### 5. Progress Tracking (Large Files)

For very large files, consider:
- Direct-to-S3 uploads (presigned URLs)
- Chunked uploads
- Background job processing

```ruby
# Use presigned URLs instead
class PresignedUploadHandler
  def self.call(request, params)
    S3_CLIENT = Aws::S3::Client.new(region: 'us-east-1')
    
    # Generate presigned URL for client to upload directly
    presigned_url = S3_CLIENT.presigned_url(
      :put_object,
      bucket: 'my-bucket',
      key: "uploads/#{SecureRandom.uuid}/file",
      expires_in: 3600
    )
    
    { upload_url: presigned_url }
  end
end
```

### 6. Virus Scanning

```ruby
class ScannedUploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    files.each do |file|
      # Save temporarily
      temp_path = "/tmp/#{SecureRandom.uuid}"
      File.binwrite(temp_path, file[:data])
      
      # Scan with ClamAV or similar
      scan_result = `clamscan #{temp_path}`
      
      if scan_result.include?('FOUND')
        File.delete(temp_path)
        return { error: "Virus detected in #{file[:filename]}" }
      end
      
      File.delete(temp_path)
    end
    
    # Files are clean, process them...
  end
end
```

## Common Patterns

### Image Thumbnails

```ruby
require 'mini_magick'

class ThumbnailHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    thumbnails = files.map do |file|
      # Create thumbnail
      image = MiniMagick::Image.read(file[:data])
      image.resize '200x200'
      
      # Save original and thumbnail
      {
        original: save_file(file[:filename], file[:data]),
        thumbnail: save_file("thumb_#{file[:filename]}", image.to_blob)
      }
    end
    
    { thumbnails: thumbnails }
  end
end
```

### CSV Import

```ruby
require 'csv'

class CSVUploadHandler
  def self.call(request, params)
    data = request.instance_variable_get(:@multipart_data)
    files = data.select { |p| p[:type] == :file }
    
    csv_file = files.find { |f| f[:filename].end_with?('.csv') }
    return { error: 'No CSV file' } unless csv_file
    
    # Parse CSV
    rows = CSV.parse(csv_file[:data], headers: true)
    
    { 
      row_count: rows.size,
      headers: rows.headers,
      sample: rows.first(5).map(&:to_h)
    }
  end
end
```

## Notes

- Files stored in memory (not suitable for very large files)
- For production, save to disk/S3 immediately
- Parser handles standard multipart/form-data format
- Validates file size and count before processing
- Thread-safe (no shared state)
- Only processes POST/PUT/PATCH requests

## Troubleshooting

**Files not parsing?**
- Check content-type includes `multipart/form-data`
- Verify boundary is present in content-type header
- Ensure request method is POST/PUT/PATCH

**File size errors?**
- Check actual file size vs `max_file_size`
- Remember limit is in bytes (10MB = 10_485_760)

**Extension validation failing?**
- Extensions must include the dot: `'.jpg'` not `'jpg'`
- Comparison is case-insensitive

**Memory issues?**
- Don't use for large files (>10MB) in production
- Save to disk/S3 immediately after parsing
- Consider direct-to-S3 uploads for large files
```