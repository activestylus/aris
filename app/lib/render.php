<?php
require_once __DIR__ . '/../config/colors.php';
define('VIEWS_PATH', __DIR__ . '/../views/');
define('CSS_PATH', __DIR__ . '/../views/css/');

class CssColorProcessor {
    private static $pattern;
    private static $colorMap;
    private static $initialized = false;
    private static $hasBrace;
    public static function init(array $colors): void {
        if (self::$initialized) return;
        $keys = array_keys($colors);
        $count = count($keys);
        $patterns = [];
        for ($i = 0; $i < $count; $i++) {
            $patterns[] = preg_quote($keys[$i], '/');
        }
        self::$pattern = '/{([^}]*?)(' . implode('|', $patterns) . ')([^}]*?)}/';
        self::$colorMap = [];
        foreach ($keys as $i => $key) {
            self::$colorMap[$key] = $colors[$key];
        }
        self::$hasBrace = '{';
        self::$initialized = true;
    }
    public static function process(string $css): string {
        if (strpos($css, self::$hasBrace) === false) {
            return $css;
        }
        return preg_replace_callback(
            self::$pattern,
            static function($matches) {
                return '{' . $matches[1] . self::$colorMap[$matches[2]] . $matches[3] . '}';
            },
            $css
        );
    }
}
CssColorProcessor::init($cssColors);
function injectCssColor(string $css): string {
    return CssColorProcessor::process($css);
}

$collectStyles = (function() {
    $styles = [];
    $count = 0;
    return [
        'add' => function($style) use (&$styles, &$count) {
            if ($style = trim($style)) {  // Assignment in condition is faster
                $styles[$count++] = injectCssColor($style);
            }
        },
        'get' => function() use (&$styles, &$count) {
            if (!$count) return '';
            $result = implode("\n", $styles);
            $styles = [];
            $count = 0;
            return $result;
        }
    ];
})();

function minify($h, $ext) {
    if (!$h) return '';  // Fast bail
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

static $pathCache = [];
static $envCache = null;

function rend(string $path, string $ext, array $locals = []): string {
    static $pathCache = [];
    static $envCache = null;  // Moved inside the function
    
    // Fast path resolution with static cache
    $cacheKey = $ext . '_' . $path;
    if (!isset($pathCache[$cacheKey])) {
        $pathCache[$cacheKey] = ($ext === 'php' ? VIEWS_PATH : CSS_PATH) . $path . '.php';
    }
    $fullPath = $pathCache[$cacheKey];
    
    // Early return for missing files
    if (!is_file($fullPath)) {
        return "Error: Unable to load view '$fullPath'.";
    }
    
    // Extract locals only if needed
    if (!empty($locals)) {
        extract($locals);
    }
    
    // Buffered include
    ob_start();
    include $fullPath;
    $output = ob_get_clean();
    
    // Fast path for non-layout renders
    if ($path !== 'layout') {
        // Cache environment check
        if ($envCache === null) {
            $envCache = myEnv();
        }
        return $envCache === 'production' ? minify($output, $ext) : $output;
    }
    
    // Layout-specific processing
    global $collectStyles;
    $allStyles = $collectStyles['get']();
    
    if ($allStyles !== '') {
        // Single str_replace when possible
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
    }
    
    // Use cached environment
    if ($envCache === null) {
        $envCache = myEnv();
    }
    
    return $envCache === 'production' ? minify($output, $ext) : $output;
}

function ui($path, $locals = []) {
    return rend($path, 'php', $locals);
}

function yieldStyle($style) {
    global $collectStyles;
    $collectStyles['add']($style);
}

function cssFile(...$paths) {
    $locals = [];
    
    if (!empty($paths) && is_array(end($paths)) && array_keys(end($paths)) !== range(0, count(end($paths)) - 1)) {
        $locals = array_pop($paths);
    }
    
    $output = '';
    foreach ($paths as $path) {
        $css = rend($path, 'css', $locals);
        $output .= injectCssColor($css);  // Only change: process colors here
    }
    
    return $output;
}
?>