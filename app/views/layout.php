<?php
$site  = "https://www.modernpressnyc.com";
$tit  = is($title,'Modern Press NYC');
$des  = is($desc,'Offset & Commercial Printing NYC');
$imag  = is($image,'/i/modernpressnyc.jpg');
$src   = $site . $imag
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title><?= $tit ?></title>
    <?= metaN('viewport','width=device-width, initial-scale=1.0') ?>
    <?= metaN('description',$des) ?>
    <?= metaP('og:title',$tit) ?>
    <?= metaP('og:description',$des) ?>
    <?= metaP('og:image',$src) ?>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black">
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png"/>
    <link rel="icon" href="/favicon-32x32.png" sizes="32x32"/>
    <meta name="theme-color" content="#ffffff"/>
    <style>
        <?= cssFile('reset','style'); ?>
        <!--YIELD_STYLES-->
        <?= is($style); ?>
<?php
media('1280',".h2mo {font-size: 1.5em;}");
media('960',".andBreak {display:block;} .h2mo {font-size: 1.4em;}");
$m768=<<<M
.h2mo {font-size: 1.3em;}
.f66,.f60,.f50,.f40,.f33{flex: 0 0 100%;}
M;
media('768',$m768);
?>
    </style>
</head>
<body>
    <main>
        <?= is($content); ?>
    </main>

    <footer class='tac'>
        <p>&copy; <?= date('Y'); ?> Our Company. All rights reserved. <a href='#privacy'>Privacy Policy</a> • <a href="#terms">Terms of Use</a> • <a href='#contact'>Contact Us</a></p>
    </footer>
</body>
</html>