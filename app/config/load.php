<?
if (!getenv('APP_ENV')) {
    putenv('APP_ENV=development'); // Default to development if not set
}

$appEnv = getenv('APP_ENV');

?>