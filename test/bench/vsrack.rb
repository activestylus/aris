require_relative "../test_helper"
# ====================================================================
# AGNOSTIC ADAPTERS AND UTILITIES (Required for Non-Rack Path)
# ====================================================================

# This module simulates the FFI layer providing minimal data.
module AgnosticAdapter
  # Simple Request object builder for non-Rack tests
  def self.build_request(method:, path:, host:, headers: {})
    # Note: Rack::Request needs the env structure, so we mock it minimally.
    mock_env = {
      'REQUEST_METHOD' => method.upcase,
      'PATH_INFO' => path,
      'HTTP_HOST' => host,
      'QUERY_STRING' => nil, 
      'rack.input' => StringIO.new(''),
    }.merge(headers)
    
    # We use the full Aris::Request class to test the object instantiation overhead
    return Aris::Request.new(mock_env)
  end
end

# Dummy Handler
class TestHandler
  # Uses the request object to force the call to be realistic
  def self.call(request, params); request.path_info; end
end

# ====================================================================
# ROUTE SETUP
# ====================================================================

# Deeply nested parameterized route for max Trie traversal depth
DEEP_ROUTE_PATH = '/api/v1/customers/:cid/orders/:oid/items/:iid'.freeze
DEEP_TEST_PATH = '/api/v1/customers/123/orders/99/items/77'.freeze

# Define routes for benchmarking
Aris::Router.define({
  "benchmark.com": {
    # Shallow parameterized route (2 segments)
    "/users/:id": { get: { to: TestHandler } },
    
    # Deep parameterized route (8 segments)
    "#{DEEP_ROUTE_PATH}": { get: { to: TestHandler, as: :deep_route } }
  }
})

# ====================================================================
# BENCHMARK SETUP
# ====================================================================

$APP = Aris::Adapters::RackApp.new
$DOMAIN = 'benchmark.com'

# Non-Rack Request Objects (Built once for use in Agnostic benchmarks)
$REQUEST_SHALLOW = AgnosticAdapter.build_request(
  method: 'GET', path: '/users/1', host: $DOMAIN
)
$REQUEST_DEEP = AgnosticAdapter.build_request(
  method: 'GET', path: DEEP_TEST_PATH, host: $DOMAIN
)

# Rack Request Environment (Built once for use in Rack benchmarks)
$ENV_SHALLOW = {
  'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/users/1', 
  'HTTP_HOST' => $DOMAIN, 'rack.input' => StringIO.new('')
}
$ENV_DEEP = {
  'REQUEST_METHOD' => 'GET', 'PATH_INFO' => DEEP_TEST_PATH, 
  'HTTP_HOST' => $DOMAIN, 'rack.input' => StringIO.new('')
}


# ====================================================================
# PERFORMANCE BENCHMARK
# ====================================================================

puts "=" * 80
puts "ROUTER DEPTH vs. ABSTRACTION OVERHEAD"
puts "=" * 80
puts "Measuring cost of Ruby Abstraction Layer vs. Pure Routing Cost."
puts ""

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  
  # ----------------------------------------------------------------
  # CORE ROUTING BASELINES (Measures router efficiency only)
  # ----------------------------------------------------------------
  
  # A. PURE ROUTING (SHALLOW)
  x.report("A. CORE ROUTE (Shallow)") do
    Aris::Router.match(domain: $DOMAIN, method: :get, path: '/users/1')
  end

  # B. PURE ROUTING (DEEP)
  x.report("B. CORE ROUTE (Deep)") do
    Aris::Router.match(domain: $DOMAIN, method: :get, path: DEEP_TEST_PATH)
  end
  
  # ----------------------------------------------------------------
  # AGNOSTIC (FFI) PATH (Measures Request Object + Routing Cost)
  # ----------------------------------------------------------------

# Apply this fix to the C. AGNOSTIC (Shallow) block:
x.report("C. AGNOSTIC (Shallow)") do
  route = Aris::Router.match(domain: $REQUEST_SHALLOW.host, method: $REQUEST_SHALLOW.request_method.downcase.to_sym, path: $REQUEST_SHALLOW.path_info)
  route[:handler].call($REQUEST_SHALLOW, route[:params]) if route
end

# And to the D. AGNOSTIC (Deep) block:
x.report("D. AGNOSTIC (Deep)") do
  route = Aris::Router.match(domain: $REQUEST_DEEP.host, method: $REQUEST_DEEP.request_method.downcase.to_sym, path: $REQUEST_DEEP.path_info)
  route[:handler].call($REQUEST_DEEP, route[:params]) if route
end
  
  # ----------------------------------------------------------------
  # RACK PATH (Measures Full Ruby Abstraction Cost)
  # ----------------------------------------------------------------
  
  # E. RACK (Shallow) - Full Rack Adapter Overhead
  x.report("E. RACK (Shallow)") do
    $APP.call($ENV_SHALLOW)
  end

  # F. RACK (Deep) - Full Rack Adapter Overhead
  x.report("F. RACK (Deep)") do
    $APP.call($ENV_DEEP)
  end

  x.compare!
end

puts "\n" + "=" * 80
puts "ANALYSIS & INSIGHTS"
puts "=" * 80
puts "1. Shallow Cost (A vs C vs E): Measures the fixed overhead of the abstraction."
puts "2. Deep Cost (B vs D vs F): Measures how the overhead scales with Trie traversal."
puts "3. Routing Efficiency (A vs B): Measures your core Trie lookup performance."
puts ""