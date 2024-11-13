<?php
// Ensure default server variables when running via CLI
if (php_sapi_name() === 'cli') {
    $_SERVER['REQUEST_METHOD'] = 'GET';
    $_SERVER['REQUEST_URI'] = '/';
}

function benchmark_memory(callable $fn, string $name) {
    $mem_start = memory_get_usage();
    $result = $fn();
    $mem_end = memory_get_usage();
    echo "$name Memory Usage: " . (($mem_end - $mem_start) / 1024) . " KB\n";
    return $result;
}

function benchmark_time(callable $fn, string $name, int $iterations) {
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) {
        $fn();
    }
    $end = microtime(true);
    echo "$name Time for $iterations iterations: " . (($end - $start) * 1000) . " ms\n";
}

// Pattern definitions - used for route parameter validation
const PATTERN = [
    'id'   => '\d+',
    'slug' => '[a-z0-9-]+',
    'any'  => '[^/]+',
    'uuid' => '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
];

function create_router(array $config = []) {
    // Internal router state
    $state = [
        'patterns' => PATTERN,
        'middleware' => [
            'auth' => function($next) {
                return empty($_SESSION['user'])
                    ? ['status' => 401, 'body' => 'Unauthorized']
                    : $next();
            },
            'csrf' => function($next) {
                $request_method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
                return $request_method === 'POST' &&
                       (!isset($_POST['_csrf']) || $_POST['_csrf'] !== ($_SESSION['_csrf'] ?? null))
                    ? ['status' => 403, 'body' => 'Invalid CSRF']
                    : $next();
            },
            'api' => function($next) {
                header('Content-Type: application/json');
                $result = $next();
                return is_array($result) ? json_encode($result) : $result;
            },
            'cache' => function($next) use (&$state) {
                $key = md5($_SERVER['REQUEST_URI'] ?? '/');
                return isset($state['cache'][$key]) ? $state['cache'][$key] : ($state['cache'][$key] = $next());
            },
            'cors' => function($next) {
                static $headers = [
                    "Access-Control-Allow-Origin: *",
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS"
                ];
                foreach($headers as $h) header($h);
                $request_method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
                return $request_method === 'OPTIONS'
                    ? (header("HTTP/1.1 200 OK") || exit())
                    : $next();
            },
            'method' => function($next) {
                static $allowed = ['GET' => true, 'POST' => true, 'PUT' => true, 'DELETE' => true, 'PATCH' => true];
                $request_method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
                return isset($allowed[$request_method])
                    ? $next()
                    : ['status' => 405, 'body' => 'Method Not Allowed'];
            }
        ],
        'named_routes' => [],
        'cache' => [],
        'compiled_routes' => []
    ];

    $process_routes = function($routes, $parent_middleware = [], $parent_path = '') use (&$state, &$process_routes) {
        static $pattern_cache = [];
        static $mw_chain_cache = [];
        $processed = [];

        // Pre-compile common middleware chains
        $mw_key = implode(',', $parent_middleware);
        if (!isset($mw_chain_cache[$mw_key])) {
            $mw_chain_cache[$mw_key] = array_merge(['method'], $parent_middleware);
        }

        foreach ($routes as $route) {
            if (!isset($route[0])) continue;

            if ($route[0] === 'group') {
                if (!isset($route[3])) continue;
                $group_path = $parent_path . $route[1];
                $group_middleware = array_merge($parent_middleware, array_column($route[2], 0));

                $children_routes = $process_routes($route[3], $group_middleware, $group_path);
                $processed = array_merge($processed, $children_routes);
                continue;
            }

            $method = $route[0];
            $path = $parent_path . $route[1];
            $handler = $route[2];
            $opts = $route[3] ?? [];
            $ids = $route[4] ?? [];

            $middleware = $mw_chain_cache[$mw_key];
            $cache = null;

            if (isset($opts['name'])) {
                $state['named_routes'][$opts['name']] = $path;
            }

            if (!empty($opts) && isset($opts[0]) && is_array($opts[0])) {
                // Middleware specified
                $chain_key = $mw_key;
                foreach ($opts as $opt) {
                    if (is_array($opt)) {
                        $mw = $opt[0];
                        if ($mw === 'cache') {
                            $cache = $opt[1];
                        } else {
                            $chain_key .= ',' . $mw;
                        }
                    }
                }
                if (!isset($mw_chain_cache[$chain_key])) {
                    $mw_chain_cache[$chain_key] = array_merge($middleware, array_column($opts, 0));
                }
                $middleware = $mw_chain_cache[$chain_key];
            }

            $param_names = [];
            $regex = null;

            if (strpos($path, ':') !== false) {
                $parts = explode('/', $path);
                $pattern_idx = 0;
                foreach ($parts as $index => $part) {
                    if ($part && $part[0] === ':') {
                        $param_name = substr($part, 1);
                        $param_names[] = $param_name;
                        $pattern_id = $ids[$pattern_idx++] ?? 'any';
                        $pattern_key = $pattern_id . ':' . $param_name;

                        if (!isset($pattern_cache[$pattern_key])) {
                            $pattern_cache[$pattern_key] = '(?P<' . $param_name . '>' . $state['patterns'][$pattern_id] . ')';
                        }
                        $parts[$index] = $pattern_cache[$pattern_key];
                    }
                }
                $regex = '#^' . implode('/', $parts) . '$#';
            }

            $processed[] = [
                $method,
                $path,
                $handler,
                $middleware,
                $cache,
                $param_names,
                $regex
            ];
        }

        return $processed;
    };

    $match_route = function($method, $path) use (&$state) {
        static $static_routes = [];
        static $dynamic_routes = [];

        if (empty($static_routes)) {
            foreach ($state['compiled_routes'] as $route) {
                if ($route[6] === null) {
                    // Static route
                    $static_routes[$route[0]][$route[1]] = [$route[2], [], $route[3], $route[4]];
                } else {
                    // Dynamic route
                    $segments = explode('/', trim($route[1], '/'));
                    $first_segment = $segments[0] ?? '';
                    $dynamic_routes[$route[0]][$first_segment][] = $route;
                }
            }
        }

        if (isset($static_routes[$method][$path])) {
            return $static_routes[$method][$path];
        }

        $segments = explode('/', trim($path, '/'));
        $first_segment = $segments[0] ?? '';

        if (isset($dynamic_routes[$method][$first_segment])) {
            foreach ($dynamic_routes[$method][$first_segment] as $route) {
                if (preg_match($route[6], $path, $matches)) {
                    $params = [];
                    foreach ($route[5] as $name) {
                        if (isset($matches[$name])) {
                            $params[$name] = $matches[$name];
                        }
                    }
                    return [
                        $route[2],
                        $params,
                        $route[3],
                        $route[4]
                    ];
                }
            }
        }

        // Check routes with dynamic first segment
        if (isset($dynamic_routes[$method][''])) {
            foreach ($dynamic_routes[$method][''] as $route) {
                if (preg_match($route[6], $path, $matches)) {
                    $params = [];
                    foreach ($route[5] as $name) {
                        if (isset($matches[$name])) {
                            $params[$name] = $matches[$name];
                        }
                    }
                    return [
                        $route[2],
                        $params,
                        $route[3],
                        $route[4]
                    ];
                }
            }
        }

        return null;
    };

    $execute_route = function($route) use (&$state) {
        if (!$route || !$route[2]) return null;

        static $chain_cache = [];
        $chain_key = implode(',', $route[2]);

        if (!isset($chain_cache[$chain_key])) {
            $handler = $route[0];
            $mw_chain = array_reverse($route[2]);

            $chain = function($params) use ($handler) {
                return $handler($params);
            };

            foreach ($mw_chain as $mw_name) {
                $current = $chain;
                $chain = function($params) use ($current, &$state, $mw_name) {
                    return $state['middleware'][$mw_name](function() use ($current, $params) {
                        return $current($params);
                    });
                };
            }

            $chain_cache[$chain_key] = $chain;
        }

        return $chain_cache[$chain_key]($route[1]);
    };

    $url = function($name, $params = []) use (&$state) {
        if (!isset($state['named_routes'][$name])) {
            return '';
        }
        $path = $state['named_routes'][$name];
        foreach ($params as $key => $value) {
            $path = str_replace(':' . $key, $value, $path);
        }
        return $path;
    };

    return [
        'compile' => function($routes) use (&$state, $process_routes) {
            $state['compiled_routes'] = $process_routes($routes);
            return $state['compiled_routes'];
        },
        'match' => $match_route,
        'execute' => $execute_route,
        'url' => $url
    ];
}

// Test Routes
$routes = [
    ['GET', '/', function() { return 'home'; }, ['name' => 'home']],
    ['GET', '/about', function() { return 'about'; }, ['name' => 'about', [['csrf'], ['cache', 300]]]],
    
    ['group', '/admin', [['auth'], ['csrf']], [
        ['GET', '/dashboard', function() { return 'dashboard'; }, ['name' => 'admin.dashboard']],
        ['GET', '/users/:id', function($params) { return "user {$params['id']}"; }, 
            ['name' => 'admin.user'], ['id']]
    ]],
    
    ['group', '/api', [['api'], ['cors']], [
        ['GET', '/users/:id/posts/:slug', function($params) { 
            return ['user' => $params['id'], 'post' => $params['slug']]; 
        }, ['name' => 'api.user.post'], ['id', 'slug']],
        ['GET', '/docs/:uuid', function($params) { 
            return ['doc' => $params['uuid']]; 
        }, ['name' => 'api.doc'], ['uuid']]
    ]]
];

// Benchmarking
echo "Starting Production Router Benchmarks...\n-------------------------\n";

$router = create_router();

$compiled_routes = benchmark_memory(function() use ($router, $routes) {
    return $router['compile']($routes);
}, "Route Compilation");

benchmark_time(function() use ($router) {
    $router['match']('GET', '/');
    $router['match']('GET', '/about');
}, "Static Route Matching", 40000);

$test_paths = [
    '/admin/users/123',
    '/api/users/456/posts/test-post',
    '/api/docs/550e8400-e29b-41d4-a716-446655440000',
    '/not/found'
];

benchmark_time(function() use ($router, $test_paths) {
    foreach ($test_paths as $path) {
        $router['match']('GET', $path);
    }
}, "Dynamic Route Matching", 10000);

benchmark_time(function() use ($router) {
    $route = $router['match']('GET', '/admin/dashboard'); 
    $router['execute']($route);
}, "Middleware Chain", 10000);

benchmark_time(function() use ($router) { 
    $router['url']('api.user.post', ['id' => 123, 'slug' => 'test-post']);
    $router['url']('admin.user', ['id' => 456]);
}, "URL Generation", 10000);

benchmark_time(function() use ($router) { 
    $router['match']('GET', '/this/does/not/exist');
}, "404 Route Handling", 10000);

benchmark_time(function() use ($router) { 
    $router['url']('invalid.route');
}, "Invalid Route Handling", 10000);

echo "\nClosure-Specific Benchmarks\n-------------------------\n";

benchmark_memory(function() {
    return create_router();
}, "Router Creation");

$router2 = create_router();
benchmark_time(function() use ($router2) {
    $router2['match']('GET', '/');
}, "Single Route Match (Closure)", 10000);

benchmark_time(function() use ($router2) {
    $route = $router2['match']('GET', '/admin/dashboard');
    if ($route) $router2['execute']($route);
}, "Full Request Cycle (Closure)", 10000);

echo "\n-------------------------\nBenchmarks Complete!\n";
