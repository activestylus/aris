<?php
$h2 = 'Modern Press: Serving the Tri-State Area';
$h3 = '683 Garfield Avenue, Jersey City';
$btn = 'Copy Google Maps Link';
$txt = 'Our shop is located just a 6 minute drive from the Holland Tunnel. Proximity to Manhattan offers efficient and accessible service to agencies, firms and creative freelancers in NYC.';
$src = '/i/map.jpg';
$css = <<<EOT
  .map {height:190px;} .mp {border:1px solid alpha-dark;}
  .mp:hover {background:#fff}
EOT;
style($css);
?>
<div class="p16 mt16 pb0 tac bac max flex bg-alpha-pale">
  <div class="f40 bcov map bgcc" style="<?= bg($src) ?>">
  </div>
  <div class="f60">
    <h2 class="p0 fw4 fs20 alpha-nite"><?= $h2 ?></h2>
    <h3>
      <span class="fs16 fw2"><?= $h3 ?></span>
      <span
        id="google" class="mp ml16 btn copy fs6 p8 tduh alpha-nite"
        data-copy="https://maps.app.goo.gl/9TX5Y2pUjMWRzHvM8">
        <?= $btn ?>
      </span>
    </h3>
    <p class="fw6 fs12 alpha-dark"><?= $txt ?></p>
  </div>
</div>
<?= ui('parts/contactBar'); ?>
<script type='text/javascript'>
document.querySelectorAll('.copy').forEach(b => {
  b.addEventListener('click', function() {
    const originalText = this.innerText;
    const textToCopy = this.dataset.copy;
    navigator.clipboard.writeText(textToCopy).then(() => {
      this.innerText = 'Copied Google Maps Link!';
      setTimeout(() => this.innerText = originalText, 3000);
    });
  });
});
</script>