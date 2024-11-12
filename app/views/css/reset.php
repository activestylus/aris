<?
$red = '#f00';
$p0 = '4px';
$p1 = '8px';
$p2 = '16px';
$p3 = '24px';
$p4 = '32px';
$gap = 16;
?>
*, *::before, *::after{box-sizing: border-box; }
*{margin:0; padding:0}
body, html { height:100%; scroll-behavior: smooth;}
html:focus-within{ scroll-behavior: smooth; }
a:not([class]){ text-decoration-skip-ink: auto; }
img, picture, svg, video, canvas{ font-style: italic; }
input, button, textarea, select{ font: inherit; }
.rel {position: relative} .abs {position:absolute}
.img, .mxw100 {max-width: 100%}
.img, .hauto {height: auto}
.vam, .vam * {vertical-align: middle; }
.vat {vertical-align: top; }
.p4 {padding:<?=$p0?>}.p8 {padding:<?=$p1?>}.p16 {padding:<?=$p2?>}
.p0{padding:0}.pb0 {padding-bottom: 0} .pt4 {padding-top: <?= $p0?>}
.px16,h1,h2,h3,h4 {padding-top:<?=$p2?>;padding-bottom:<?=$p2?>}
.py16 {padding-left: <?=$p2?>;padding-right: <?=$p2?>}
.px8,p {padding-top:<?=$p1?>;padding-bottom:<?=$p1?>}
.mt16 {margin-top:<?=$p2?>}
.mr16 {margin-right:<?=$p2?>}
.ml16 {margin-left:<?=$p2?>}
.bac {margin-left:auto;margin-right:auto}
.max {max-width:1800px}
.tdn,.tdn:hover,.tduh, .tduh * {text-decoration: none}
.tduh:hover, .tduh *:hover {text-decoration: underline}
@font-face {
  font-family: 'Karla';
  src: url('/f/Karla.ttf') format('truetype-variations');
  font-weight: 200 800;
  font-style: normal;
}
.hero, .bcov {background-size:cover}
.bgcc {background-position: center center;}
.bfff{background-color:#fff}
.bg-alpha-pale {background:alpha-pale}
.bg-alpha-lite {background:alpha-lite}
.alpha-dark {color:alpha-dark}
a,.alpha-nite {color:alpha-nite}
body {font-family: 'Karla', sans-serif; font-weight: 400;}
p {line-height:1.55em}
.caps {text-transform: uppercase}
.tac {text-align: center}
.fw2 {font-weight: 200}
.fw6 {font-weight: 600}
.fw7 {font-weight: 700}
.fw8 {font-weight: 800}
.fs6 {font-size: .8em}
.fs8 {font-size: .8em}
.fs10 {font-size: 1em}
.fs12 {font-size: 1.2em}
.fs14 {font-size: 1.4em}
.fs16 {font-size: 1.6em}
.fs18 {font-size: 1.8em}
.fs20 {font-size: 2.0em}
.fs24 {font-size: 2.4em}
.fs27 {font-size: 2.7em}
.fs32 {font-size: 3.2em}
.db {display: block}.dib {display: inline-block}
.flex {display: flex; flex-wrap: wrap; width: 100%; gap:<?=$gap?>px}
.f50 {flex: 0 0 calc(50% - <?= $gap / 2 ?>px)}
.f40 {flex: 0 0 calc(40% - <?= $gap / 2 ?>px)}
.f33 {flex: 0 0 calc(33% - <?= $gap / 2 ?>px)}
.f60 {flex: 0 0 calc(60% - <?= $gap / 2 ?>px)}
.andBreak {display: none;}
.h2mo {font-size: 1.7em;}