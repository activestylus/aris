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
function hex_encode($str) {$hex = ''; for ($i = 0; $i < strlen($str); $i++) {$hex .= '%' . bin2hex($str[$i]);}return $hex;}
function emailTo($text, $email) {return sprintf( '<a class="dib" href="mailto:%s">%s</a>', hex_encode($email), htmlspecialchars($text, ENT_QUOTES, 'UTF-8'));}
function phoneTo($text, $phone) {return sprintf('<a class="dib" href="tel:%s">%s</a>',hex_encode($phone),htmlspecialchars($text, ENT_QUOTES, 'UTF-8'));}

?>