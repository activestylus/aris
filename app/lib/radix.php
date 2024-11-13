<?php
function benchmark_memory(callable $fn, string $name) {
    $mem_start = memory_get_usage(); $result = $fn();
    $mem_end = memory_get_usage();
    echo "$name Memory Usage: " . (($mem_end - $mem_start) / 1024) . " KB\n";return $result;
}
function benchmark_time(callable $fn, string $name, int $iterations) {
    $start = microtime(true);
    for ($i = 0; $i < $iterations; $i++) { $fn(); }
    $end = microtime(true);
    echo "$name Time for $iterations iterations: " . (($end - $start) * 1000) . " ms\n";
}
// Pattern definitions - used for route parameter validation
const PATTERN = [ 'id'   => '\d+', 'slug' => '[a-z0-9-]+',
    'any'  => '[^/]+', 'uuid' => '[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
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
                return $_SERVER['REQUEST_METHOD'] === 'POST' && 
                       (!isset($_POST['_csrf']) || $_POST['_csrf'] !== $_SESSION['_csrf'])
                    ? ['status' => 403, 'body' => 'Invalid CSRF']
                    : $next();
            },
            'api' => function($next) {
                header('Content-Type: application/json');
                $result = $next();
                return is_array($result) ? json_encode($result) : $result;
            },
            'cache' => function($next) use (&$state) {
                $key = md5($_SERVER['REQUEST_URI']);
                return isset($state['cache'][$key]) ? $state['cache'][$key] : ($state['cache'][$key] = $next());
            },
            'cors' => function($next) {
                static $headers = [
                    "Access-Control-Allow-Origin: *",
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS"
                ];
                foreach($headers as $h) header($h);
                return $_SERVER['REQUEST_METHOD'] === 'OPTIONS' 
                    ? (header("HTTP/1.1 200 OK") || exit())
                    : $next();
            },
            'method' => function($next) {
                static $allowed = ['GET' => 1, 'POST' => 1, 'PUT' => 1, 'DELETE' => 1, 'PATCH' => 1];
                return isset($allowed[$_SERVER['REQUEST_METHOD']])
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
        $processed_idx = 0;
        $routes_len = count($routes);
        // Pre-compile common middleware chains
        $mw_key = implode(',', $parent_middleware);
        if (!isset($mw_chain_cache[$mw_key])) {
            $mw_chain_cache[$mw_key] = array_merge(['method'], $parent_middleware);
        }
        for($i = 0; $i < $routes_len; ++$i) {
            $route = &$routes[$i];
            if (!isset($route[0])) continue;
            if ($route[0] === 'group') {
                if (!isset($route[3])) continue;
                $group_path = $parent_path . $route[1];
                $mw_configs = &$route[2];
                $mw_len = count($mw_configs);
                
                $group_middleware = $parent_middleware;
                for($j = 0; $j < $mw_len; ++$j) {
                    $mw = &$mw_configs[$j];
                    if (isset($mw[0])) $group_middleware[] = $mw[0];
                }
                
                $children_routes = $process_routes($route[3], $group_middleware, $group_path);
                $children_len = count($children_routes);
                
                for($k = 0; $k < $children_len; ++$k) {
                    $processed[$processed_idx++] = $children_routes[$k];
                }
                continue;
            }
            if (!isset($route[2])) continue;
            $method = $route[0];
            $path = $parent_path . $route[1];
            $handler = $route[2];
            $cache = null;
            $pattern_ids = null;
            $middleware = $mw_chain_cache[$mw_key];
            if (isset($route[3])) {
                $opts = &$route[3];
                if (isset($opts['name'])) {
                    $state['named_routes'][$opts['name']] = $path;
                }
                if (isset($opts[0])) {
                    if (isset($opts[0][0])) {
                        $chain_key = $mw_key;
                        $mw_len = count($opts);
                        for($m = 0; $m < $mw_len; ++$m) {
                            $mw = &$opts[$m];
                            if ($mw[0] === 'cache') {
                                $cache = $mw[1];
                            } else {
                                $chain_key .= ',' . $mw[0];
                            }
                        }
                        if (!isset($mw_chain_cache[$chain_key])) {
                            $mw_chain_cache[$chain_key] = array_merge($middleware, array_column($opts, 0));
                        }
                        $middleware = $mw_chain_cache[$chain_key];
                    } else {
                        $pattern_ids = $opts;
                    }
                }
            }
            if (isset($route[4]) || $pattern_ids) {
                $ids = isset($route[4]) ? $route[4] : $pattern_ids;
                $parts = explode('/', $path);
                $parts_len = count($parts);
                $param_names = [];
                $pattern_idx = 0;
                $pattern_key = '';
                for($n = 0; $n < $parts_len; ++$n) {
                    $part = &$parts[$n];
                    if ($part && $part[0] === ':') {
                        $param_names[] = substr($part, 1);
                        $pattern_id = $ids[$pattern_idx++];
                        $pattern_key .= $pattern_id;
                        
                        if (!isset($pattern_cache[$pattern_id])) {
                            $pattern_cache[$pattern_id] = '(' . $state['patterns'][$pattern_id] . ')';
                        }
                        $parts[$n] = $pattern_cache[$pattern_id];
                    }
                }
                $path = implode('/', $parts);
                $regex_key = "$method:$path";
                if (!isset($pattern_cache[$regex_key])) {
                    $pattern_cache[$regex_key] = "#^$path$#";
                }
                $processed[$processed_idx++] = [
                    $method,
                    $path,
                    $handler,
                    $middleware,
                    $cache,
                    $param_names,
                    $pattern_cache[$regex_key]
                ];
            } else {
                $processed[$processed_idx++] = [
                    $method,
                    $path,
                    $handler,
                    $middleware,
                    $cache,
                    [],
                    null
                ];
            }
        }

        return $processed;
    };

    $match_route = function($method, $path) use (&$state) {
        static $static_routes = []; static $dynamic_routes = [];
        
        if (empty($static_routes)) {
            foreach ($state['compiled_routes'] as $route) {
                if ($route[6] === null) {$static_routes[$route[0]][$route[1]] = [$route[2],[],$route[3],$route[4]];}
                else {
                    if (!isset($dynamic_routes[$route[0]])) $dynamic_routes[$route[0]] = [];
                    $dynamic_routes[$route[0]][] = [$route[2],$route[5],$route[3],$route[4],$route[6]];
                }
            }
        }
        
        if (isset($static_routes[$method][$path])) return $static_routes[$method][$path];
        
        if (isset($dynamic_routes[$method])) {
            foreach ($dynamic_routes[$method] as $route) {
                if (preg_match($route[4], $path, $matches)) {
                    array_shift($matches);
                    return [$route[0],$route[1]?array_combine($route[1],$matches):$matches,$route[2],$route[3]];
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
            $chain_len = count($mw_chain);
            
            $chain = function($params) use ($handler) {
                return $handler($params);
            };
            
            for($i = 0; $i < $chain_len; ++$i) {
                $mw_name = $mw_chain[$i];
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
    foreach ($test_paths as $path) {$router['match']('GET', $path);}
}, "Dynamic Route Matching", 10000);

benchmark_time(function() use ($router) {
    $route = $router['match']('GET', '/admin/dashboard'); $router['execute']($route);
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

benchmark_memory(function() {return create_router();}, "Router Creation");

$router2 = create_router();
benchmark_time(function() use ($router2) { 
    $router2['match']('GET', '/');
}, "Single Route Match (Closure)", 10000);

benchmark_time(function() use ($router2) { 
    $route = $router2['match']('GET', '/admin/dashboard');
    if ($route) $router2['execute']($route);
}, "Full Request Cycle (Closure)", 10000);

echo "\n-------------------------\nBenchmarks Complete!\n";