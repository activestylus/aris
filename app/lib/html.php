<?
function link_to($text, $url, $options = []) {
    $attrs = '';
    foreach ($options as $key => $value) {$attrs .= ' ' . $key . '="' . htmlspecialchars($value, ENT_QUOTES, 'UTF-8') . '"';}
    return '<a href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '"' . $attrs . '>' . htmlspecialchars($text, ENT_QUOTES, 'UTF-8') . '</a>';
}
function metaN($n,$c) {return "<meta name='$n' content='$c'/>";}
function metaP($n,$c) {return "<meta property='$n' content='$c'/>";}
function bg($str) { return "background-image:url($str)"; }
function is($variable, $default = '') {return isset($variable) ? $variable : $default;}
function andBreak($str) {return str_replace('&','&<br class="andBreak">',$str);}


function toLayout($path, callable $fn): string {
    error_log("toLayout starting with path: " . $path);
    
    ob_start();
    try {
        error_log("Calling function in toLayout");
        $fn();
        $content = ob_get_clean();
        error_log("Content length generated: " . strlen($content));
        
        // Debug the content structure
        error_log("First 100 chars of content: " . substr($content, 0, 100));
        
        return $content;
    } catch (Throwable $e) {
        ob_end_clean();
        error_log("Error in toLayout: " . $e->getMessage());
        error_log("Stack trace: " . $e->getTraceAsString());
        return "Error in layout: " . $e->getMessage();
    }
}

// Also add this to your layout.php right before the content is rendered:
error_log("Layout content variable exists: " . (isset($content) ? "yes" : "no"));
error_log("Layout content length: " . (isset($content) ? strlen($content) : 0));
?>