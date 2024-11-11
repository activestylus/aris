
<?php
error_reporting(-1);
ini_set('display_errors', 1);
ini_set('html_errors', 1);
require_once __DIR__ . '/../app/app.php';

yieldStyle(cssFile('home'));
$h = [
  'title' => "Offset & Specialty Commercial Print Shop | Modern Press NYC",
  'desc'  => "Premium stocks and quality printing for business cards, stationery, folders, books, booklets, flyers",
  'image' => "/i/modernpressnyc.jpg",
  'h1'    => "Commercial Offset, Digital & Specialty Printing Services",
  'cta'   => "Request a Price Quote",
  'wowH'  => 'Wow Factor',
  'wowL'  => ["Flawless Execution", "Premium Materials", "An Artist's Touch"],
  'colorH'=> 'Vivid Colors & Stunning Quality',
  'colorT'=> "Full Color • CMYK Printing • Spot/Pantone Available",
  'group1'=> [
    ["Business Card Printing",
     "#business-cards", "Large Run Offset & Short Run Digital"],
    ["Embossed Business Cards",
     "#business-cardsembossed", "Debossed, Blind & Registered Embossing"],
    ["Foil Stamp Cards",
     "#business-cardsfoil", "Available in Gold, Silver, Copper"],
    ["Thermography Cards",
     "#business-cardsraised-print", "Raised Ink, Available in Color"]],
  'group2'=> [
    ["Business Letterhead",
     "#letterhead", "Variety of Stocks & Finishes"],
    ["Custom Envelopes",
     "#envelopes", "Printed Exterior + Specialty Stocks"],
    ["Custom Note Pads",
     "#notepads", "Spiral, Perforated or Adhesive Binding"],
    ["Branded Folders",
     "#folders", "Available in Multiple Stocks/Weights"]],
  'pubH' => "Publishing Services for Creative Professionals",
  'pubT' => "Turn your PDFs & Indesign Files into publications, available in a wide array of materials and formats.",
  'pub1'=> ['Stapled, Saddle Stitch & Spiral Bound', [
    ['Annual Reports', '#annual-report-printing'],
    ['Catalogs', '#catalogs'],
    ['Fashion Lookbooks', '#fashion-lookbooks'] ]],
  'pub2'=> ['Soft-Cover Perfect Binding', [
    ['Booklets', '#booklet-printing'],
    ['Magazines', '#magazine-printing'],
    ['Paperback Books', '#paperback-publishing'] ]],
  'pub3'=> ['Hard-Cover Case Binding', [
    ['Coffee Table Books', '#coffee-table-books'],
    ['Text Books', '#hardcover-publishing'],
    ['Year Books', '#yearbook-printing'] ]]
];
$h['content'] = toLayout('content', function()  use ($h) { ?>

  <div class="hero main tac" style="<?= bg('/i/home/heroes/main/1800.jpg') ?>">
    <div class="bac max">
      <?= ui('parts/header', ['h' => $h]); ?>
      <h1 class='fw8 fff tsh'><?= andBreak($h['h1']); ?></h1>
      <a href="#" class="black20 dib btn act white2 fs18 fw6 tduh tsh bsh"><?= $h['cta'] ?></a>
    </div>
  </div>
  
  <?= ui('parts/a50', ['group' => $h['group1']]); ?>
  <? $hcls = 'hero line tac bac max' ?>
  <div class="<?=$hcls?> wow" style="<?= bg('/i/home/heroes/wow/1800.jpg') ?>">
      <h2 class='fs32 fw8 fff tsh'><?= $h['wowH'] ?></h2>
      <ul class="checks dib fs18 fff tsh">
        <? foreach ($h['wowL'] as $l): ?>
        <li><?= $l ?></li>
        <? endforeach; ?>
      </ul>
  </div>

  <?= ui('parts/map') ?>

  <?= ui('parts/a50', ['group' => $h['group2']]); ?>

  <div class="<?=$hcls?> colors" style="<?= bg('/i/home/heroes/colors/1800.jpg') ?>">
    <h2 class='fs32 fw8 fff tsh'><?= $h['colorH'] ?></h2>
    <p class='fff fs16 tsh'><?= $h['colorT']?></p>
  </div>

  <div class="bg-alpha-pale tac">
    <h2 class="fs32 fw2 alpha-nite"><?= $h['pubH']?></h2>
    <p class="p0 fs14"><?= $h['pubT']?></p>
    <br>
  

    <? foreach (['pub1','pub2','pub3'] as $pub):?>
      <? $p = $h[$pub] ?>
      <div class="pub tac">
        <h3 class='fs24 alpha-dark'><?= $p[0]?></h3>
        <?= ui('parts/a33', [ 'group' => $p[1] ]); ?>
      </div>
    <? endforeach; ?>
  </div>

<? }); echo ui('layout', $h); ?>