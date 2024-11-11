<?
function link_to($text, $url, $options = []) {
    $attrs = '';
    foreach ($options as $key => $value) {$attrs .= ' ' . $key . '="' . htmlspecialchars($value, ENT_QUOTES, 'UTF-8') . '"';}
    return '<a href="' . htmlspecialchars($url, ENT_QUOTES, 'UTF-8') . '"' . $attrs . '>' . htmlspecialchars($text, ENT_QUOTES, 'UTF-8') . '</a>';
}
function metaN($n,$c) {return "<meta name='$n' content='$c'/>";}
function metaP($n,$c) {return "<meta property='$n' content='$c'/>";}
function bg($str) { return "background-image:url($str)"; }
function toLayout($name, $cb) { ob_start();  $cb(); return ob_get_clean();}
function is($variable, $default = '') {return isset($variable) ? $variable : $default;}
function andBreak($str) {return str_replace('&','&<br class="andBreak">',$str);}
?>