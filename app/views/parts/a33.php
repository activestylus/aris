<?
$css = <<<EOT
.a33 {padding-top:25%;  border-radius:4px}
.a33:hover strong {color:black; text-decoration:underline}
EOT; 
yieldStyle($css);
?>
<div class="group flex bac max p16">
<? foreach ($group as $g): ?>
  <? $f = str_replace(' ', '', $g[0]); ?>
  
  <a href="<?= $g[1] ?>" class="a33 lite-px f33 bcov img tdn" style="<?= bg('/i/a50/' . $f . '/960.jpg'); ?>">
    <span class="db inf bfff rel p4">
      <strong class="db p8 fs12 fw7"><?= $g[0] ?></strong>

    </span>
  </a>
<? endforeach; ?> 
</div>