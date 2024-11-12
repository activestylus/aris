<?php
$css = <<<C
.a50 {padding-top:25%;  border-radius:4px}
.a50 .more {bottom:16px;right:12px}
.a50 .more:hover {background:#ccc;color:#000}
C;
style($css);
$mob = <<<C
body .a50 { padding-top: 65%; }
C;
media('768',$mob);
?>
<div class="group flex bac max p16">
<?php foreach ($group as $g): ?>
  <?php $f = str_replace(' ', '', $g[0]); // Added semicolon ?>
  
  <a href="<?= $g[1] ?>" class="a50 lite-px f50 bcov img tdn" style="<?= bg('/i/a50/' . $f . '/960.jpg') ?>">
    <span class="db inf bfff rel p4">
      <strong class="db p8 pb0 fs12 fw7"><?= $g[0] ?></strong>
      <small class="db p8 pt4 fs10"><?= $g[2] ?></small>
      <span class="btn more p8 lite-px abs">More Info</span>
    </span>
  </a>
<?php endforeach; // Added semicolon ?> 
</div>