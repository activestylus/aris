<?php
require_once __DIR__ . '/../config/colors.php';

define('VIEWS_PATH', __DIR__ . '/../views/');
define('CSS_PATH', __DIR__ . '/../views/css/');

// Config module using closure
function config($key = null) {
    static $config = null;
    
    if ($config === null) {
        $config = require __DIR__ . '/../config/defaults.php';
    }
    
    if ($key === null) {
        return $config;
    }
    
    if (strpos($key, '.') !== false) {
        $parts = explode('.', $key);
        $value = $config;
        foreach ($parts as $part) {
            if (!isset($value[$part])) {
                return null;
            }
            $value = $value[$part];
        }
        return $value;
    }
    
    return $config[$key] ?? null;
}


// Color processor module
$colorProcessor = (function() use ($cssColors) {
    $pattern = null;
    $colorMap = null;
    $initialized = false;
    $hasBrace = '{';
    
    return [
        'init' => function() use (&$pattern, &$colorMap, &$initialized, $cssColors) {
            if ($initialized) return;
            $keys = array_keys($cssColors);
            $patterns = array_map(function($key) {
                return preg_quote($key, '/');
            }, $keys);
            $pattern = '/{([^}]*?)(' . implode('|', $patterns) . ')([^}]*?)}/';
            $colorMap = array_combine($keys, array_values($cssColors));
            $initialized = true;
        },
        'process' => function($css) use (&$pattern, &$colorMap, &$hasBrace) {
            if (strpos($css, $hasBrace) === false) {
                return $css;
            }
            return preg_replace_callback(
                $pattern,
                function($matches) use ($colorMap) {
                    return '{' . $matches[1] . $colorMap[$matches[2]] . $matches[3] . '}';
                },
                $css
            );
        }
    ];
})();

$colorProcessor['init']();

function injectCssColor(string $css): string {
    global $colorProcessor;
    return $colorProcessor['process']($css);
}

// Styles collector module
$styleCollector = (function() {
    $breakpoints = config('mediaBreakpoints');
    $mediaQueries = array_fill_keys($breakpoints, []);
    $mediaCount = array_fill_keys($breakpoints, 0);
    $mediaHashes = array_fill_keys($breakpoints, []); // Track unique styles per breakpoint
    
    $styles = [];
    $count = 0;
    
    return [
        'add' => function($style) use (&$styles, &$count) {
            if ($style = trim($style)) {
                $styles[$count++] = injectCssColor($style);
            }
        },
        'addMedia' => function($breakpoint, $style) use (&$mediaQueries, &$mediaCount, &$mediaHashes) {
            if (isset($mediaQueries[$breakpoint]) && ($style = trim($style))) {
                $hash = md5($style);
                if (!in_array($hash, $mediaHashes[$breakpoint])) {
                    $mediaQueries[$breakpoint][$mediaCount[$breakpoint]++] = injectCssColor($style);
                    $mediaHashes[$breakpoint][] = $hash;
                }
            }
        },
        'get' => function() use (&$styles, &$mediaQueries, &$count, &$mediaCount) {
            $result = [];
            
            if ($count) {
                $result[] = implode("\n", $styles);
                $styles = [];
                $count = 0;
            }
            
            foreach ($mediaQueries as $breakpoint => $styles) {
                if (!empty($styles)) {
                    $result[] = "@media (max-width: {$breakpoint}px) {\n" . 
                               implode("\n", $styles) . 
                               "\n}";
                    $mediaQueries[$breakpoint] = [];
                    $mediaCount[$breakpoint] = 0;
                }
            }
            
            return implode("\n", $result);
        }
    ];
})();

// Cache module
$cache = (function() {
    $pathCache = [];
    $envCache = null;
    
    return [
        'getPath' => function($key) use (&$pathCache) {
            return $pathCache[$key] ?? null;
        },
        'setPath' => function($key, $value) use (&$pathCache) {
            $pathCache[$key] = $value;
        },
        'getEnv' => function() use (&$envCache) {
            if ($envCache === null) {
                $envCache = myEnv();
            }
            return $envCache;
        }
    ];
})();

// Existing functions modified to use the modules
function toLayout($path, callable $fn): string {
    ob_start();
    try {
        error_log("Calling function in toLayout");
        $fn();
        $content = ob_get_clean();
        error_log("Content length generated: " . strlen($content));
        error_log("First 100 chars of content: " . substr($content, 0, 100));
        return $content;
    } catch (Throwable $e) {
        ob_end_clean();
        error_log("Error in toLayout: " . $e->getMessage());
        error_log("Stack trace: " . $e->getTraceAsString());
        return "Error in layout: " . $e->getMessage();
    }
}

function minify($h, $ext) {
    if (!$h) return '';
    static $php_replacements = [
        '/<!--[\s\S]*?-->/' => '',
        '/\/\*[\s\S]*?\*\//' => '',
        '/>\s+</' => '><',
        '/^\s+|\s+$/m' => '',
        '/\s{2,}/' => ' '
    ];
    static $css_replacements = [
        '!/\*.*?\*/!s' => '',
        '/\s+/' => ' ',
        '/;(?=\s*})/' => ''
    ];
    static $css_str_replacements = [
        ': ' => ':',
        ' :' => ':',
        ' ;' => ';',
        '; ' => ';',
        ' {' => '{',
        '{ ' => '{',
        ' }' => '}',
        '} ' => '}'
    ];
    
    if ($ext === 'php') {
        foreach ($php_replacements as $pattern => $replacement) {
            $h = preg_replace($pattern, $replacement, $h);
        }
        return trim(str_replace(["\r\n", "\r", "\n"], '', $h));
    }
    if ($ext === 'css') {
        foreach ($css_replacements as $pattern => $replacement) {
            $h = preg_replace($pattern, $replacement, $h);
        }
        return trim(strtr($h, $css_str_replacements));
    }
    return $h;
}

function rend(string $path, string $ext, array $locals = []): string {
    global $cache, $styleCollector;
    
    error_log("Rendering: " . $path . " with extension: " . $ext);
    
    $cacheKey = $ext . '_' . $path;
    $fullPath = $cache['getPath']($cacheKey);
    
    if (!$fullPath) {
        $fullPath = ($ext === 'php' ? VIEWS_PATH : CSS_PATH) . $path . '.php';
        error_log("Full path resolved to: " . $fullPath);
        error_log("File exists: " . (file_exists($fullPath) ? "yes" : "no"));
        error_log("Is readable: " . (is_readable($fullPath) ? "yes" : "no"));
        $cache['setPath']($cacheKey, $fullPath);
    }
    
    if (!is_file($fullPath)) {
        $error = "Unable to load view: $fullPath";
        error_log($error);
        return $error;
    }
    
    if (!empty($locals)) {
        extract($locals);
    }
    
    ob_start();
    try {
        include $fullPath;
        $output = ob_get_clean();
    } catch (Throwable $e) {
        ob_end_clean();
        error_log("Error in include: " . $e->getMessage());
        error_log("Stack trace: " . $e->getTraceAsString());
        return "Error in view: " . $e->getMessage();
    }
    
    if ($path !== 'layout') {
        return $cache['getEnv']() === 'production' ? minify($output, $ext) : $output;
    }
    
    $allStyles = $styleCollector['get']();
    
    if ($allStyles !== '') {
        $output = preg_replace('/@media\s*\([^)]+\)\s*{\s*<!\s*yield\s+\d+\s*>\s*}/', '', $output);
        
        if (isset($locals['style'])) {
            $styleTarget = $locals['style'];
            $styleReplacement = $allStyles . "\n" . $styleTarget;
            $output = str_replace(
                ['<!--YIELD_STYLES-->', $styleTarget],
                [$allStyles, $styleReplacement],
                $output
            );
        } else {
            $output = str_replace('<!--YIELD_STYLES-->', $allStyles, $output);
        }
        
        $output = preg_replace('/(@media[^{]+{\s*})\s*/', '', $output);
    }
    
    return $cache['getEnv']() === 'production' ? minify($output, $ext) : $output;
}

function ui($path, $locals = []) {
    return rend($path, 'php', $locals);
}

function layout($path, $locals = []) {
    
    $defaultLayoutVars = config('layouts');
    
    $layoutType = basename($path);
    
    if (isset($defaultLayoutVars[$layoutType])) {
        $locals = array_merge($defaultLayoutVars[$layoutType], $locals);
    }
    
    return rend($path, 'php', $locals);
}

function style($style) {
    global $styleCollector;
    $styleCollector['add']($style);
}

function media($breakpoint, $style) {
    global $styleCollector;
    $styleCollector['addMedia']($breakpoint, $style);
}

function cssFile(...$paths) {
    $locals = [];
    
    if (!empty($paths) && is_array(end($paths)) && array_keys(end($paths)) !== range(0, count(end($paths)) - 1)) {
        $locals = array_pop($paths);
    }
    
    $output = '';
    foreach ($paths as $path) {
        $css = rend($path, 'css', $locals);
        $output .= injectCssColor($css);
    }
    
    return $output;
}