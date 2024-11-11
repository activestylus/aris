<?php
require_once __DIR__ . '/config/load.php';
require_once __DIR__ . '/config/colors.php';
require_once __DIR__ . '/lib/render.php';
require_once __DIR__ . '/lib/html.php';


function isDev() {return getenv('APP_ENV') == 'development';}
function isLive() {return getenv('APP_ENV') == 'production';}


?>