<?php $a =['Home' => '/',
        'Estimate' => '#',
        'About Us' => '#',
        'Contact' => '#'];
?>
<header class='vam caps'>
    <?= ui('logo'); ?>
    <nav class='dib fs14 fw7 fff'>
        <?php foreach ($a as $k => $v): ?>
            <?= link_to($k, $v, ['class'=>'tduh fff tsh dib px8 py16']) ?>
        <?php endforeach; ?>
    </nav>
</header>