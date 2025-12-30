require_relative '../test_helper'

class BenchHandler; end
class UserHandler; end
class PostHandler; end
class CommentHandler; end

puts "ENJOY::ROUTER PERFORMANCE BENCHMARK"
puts "=" * 80

puts "BASELINE: Raw Hash Lookup"
simple_hash = {
  "example.com:GET:/users" => {get: {to: BenchHandler}},
  "example.com:GET:/users/123" => {get: {to: BenchHandler}}
}
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("raw hash lookup") { simple_hash["example.com:GET:/users"] }
end

puts "COMPILATION PERFORMANCE"
def generate_config(num_routes)
  config = { "example.com": {} }
  domain_config = config[:"example.com"]
  num_routes.times do |i|
    domain_config["/route#{i}"] = { get: { to: BenchHandler, as: :"route#{i}" } }
  end
  config
end
[10, 100, 1_000].each do |size|
  config = generate_config(size)
  time = Benchmark.measure { Aris::Router.define(config) }
  puts "#{size.to_s.rjust(6)} routes: #{(time.real * 1000).round(2)}ms"
end

puts "MATCH PERFORMANCE: Simple Routes"
Aris::Router.define({
  "example.com": {
    "/": { get: { to: BenchHandler } },
    "/users": { get: { to: BenchHandler } },
    "/posts": { get: { to: BenchHandler } }
  }
})
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("root path") { Aris::Router.match(domain: "example.com", method: :get, path: "/") }
  x.report("literal match") { Aris::Router.match(domain: "example.com", method: :get, path: "/users") }
  x.compare!
end

puts "MATCH PERFORMANCE: Parameterized Routes"
Aris::Router.define({
  "example.com": {
    "/users/:id": { get: { to: UserHandler } },
    "/users/:user_id/posts/:post_id": { get: { to: PostHandler } },
    "/users/:user_id/posts/:post_id/comments/:comment_id": { get: { to: CommentHandler } }
  }
})
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("1 param") { Aris::Router.match(domain: "example.com", method: :get, path: "/users/123") }
  x.report("2 params") { Aris::Router.match(domain: "example.com", method: :get, path: "/users/123/posts/456") }
  x.report("3 params") { Aris::Router.match(domain: "example.com", method: :get, path: "/users/123/posts/456/comments/789") }
  x.compare!
end

puts "MATCH PERFORMANCE: Priority Resolution"
Aris::Router.define({
  "example.com": {
    "/files": {
      "/readme.md": { get: { to: BenchHandler } },
      "/:id": { get: { to: BenchHandler } },
      "/*path": { get: { to: BenchHandler } }
    }
  }
})
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("literal") { Aris::Router.match(domain: "example.com", method: :get, path: "/files/readme.md") }
  x.report("param") { Aris::Router.match(domain: "example.com", method: :get, path: "/files/123") }
  x.report("wildcard") { Aris::Router.match(domain: "example.com", method: :get, path: "/files/docs/guide.md") }
  x.compare!
end

puts "MATCH PERFORMANCE: Domain Resolution"
Aris::Router.define({
  "example.com": { "/users": { get: { to: BenchHandler } } },
  "api.example.com": { "/users": { get: { to: BenchHandler } } },
  "*": { "/health": { get: { to: BenchHandler } } }
})
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("exact domain") { Aris::Router.match(domain: "example.com", method: :get, path: "/users") }
  x.report("wildcard domain") { Aris::Router.match(domain: "unknown.com", method: :get, path: "/health") }
  x.report("wildcard fallback") { Aris::Router.match(domain: "example.com", method: :get, path: "/health") }
  x.compare!
end

puts "PATH HELPER PERFORMANCE"
Aris::Router.define({
  "example.com": {
    "/users": { get: { to: BenchHandler, as: :users } },
    "/users/:id": { get: { to: UserHandler, as: :user } },
    "/users/:user_id/posts/:post_id": { get: { to: PostHandler, as: :user_post } }
  }
})
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)
  x.report("simple path") { Aris.path("example.com", :users) }
  x.report("1 param") { Aris.path("example.com", :user, id: 123) }
  x.report("2 params") { Aris.path("example.com", :user_post, user_id: 123, post_id: 456) }
  x.compare!
end

puts "MEMORY ALLOCATION"
Aris::Router.define({
  "example.com": {
    "/users": { get: { to: BenchHandler } },
    "/users/:id": { get: { to: UserHandler, as: :user } }
  }
})
Benchmark.memory do |x|
  x.report("literal match") { Aris::Router.match(domain: "example.com", method: :get, path: "/users") }
  x.report("param match") { Aris::Router.match(domain: "example.com", method: :get, path: "/users/123") }
  x.report("path helper") { Aris.path("example.com", :user, id: 123) }
  x.compare!
end