<?php
$css = <<<c
.a33 {padding-top:25%;  border-radius:4px}
.a33:hover strong {color:black; text-decoration:underline}
c;
style($css);
$mob = <<<c
body .a33 { padding-top: 65%; }
c;
media('768',$mob);
?>
<div class="group flex bac max p16">
  <?php foreach ($group as $g): ?>
    <?php $f = str_replace(' ', '', $g[0]); ?>
    <a href="<?= $g[1] ?>" class="a33 lite-px f33 bcov img tdn" style="<?= bg('/i/a50/' . $f . '/960.jpg') ?>">
      <span class="db inf bfff rel p4">
        <strong class="db p8 fs12 fw7"><?= $g[0] ?></strong>
      </span>
    </a>
  <?php endforeach; ?>
</div>