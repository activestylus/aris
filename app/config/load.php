<?php
// Put this in app/config/env.php or at the start of app/app.php

function myEnv(): string {
    static $environment = null;
    
    if ($environment !== null) {
        return $environment;
    }

    // First check existing environment variable
    $envVar = getenv('APP_ENV');
    if ($envVar) {
        $environment = $envVar;
        return $environment;
    }
    
    // Auto-detect based on server variables
    $isLocal = isset($_SERVER['HTTP_HOST']) && (
        in_array($_SERVER['HTTP_HOST'], ['localhost', '127.0.0.1']) ||
        strpos($_SERVER['HTTP_HOST'], '.test') !== false ||
        strpos($_SERVER['HTTP_HOST'], '.local') !== false
    );
    
    $environment = $isLocal ? 'development' : 'production';
    
    // Set it in environment
    putenv("APP_ENV={$environment}");
    
    return $environment;
}