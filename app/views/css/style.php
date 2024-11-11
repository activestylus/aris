<? $shade = '3px 3px 2px rgba(0, 0, 0, 0.3)'; ?>
svg#logo {width: 420px;}
svg#logo * {fill:#fff;filter: drop-shadow(<?=$shade?>)}
.tsh {text-shadow: <?=$shade?>;}
.bsh {box-shadow: <?=$shade?>;}
.rd12,.btn {border-radius:12px;}
.btn {cursor:pointer}
.btn.act {padding:12px 24px;}
.fff {color:white}
.black20 {background:rgba(0,0,0,.2)}
.main .btn {color:white}
.hero.main .btn:hover {color:gold;border-color:gold}
.white2 {border:2px solid white;}
.lite-px {border:1px solid #ccc;}

.checks li {
  list-style: none;
  padding-left: 1.5em;
  position: relative;
}

.checks li::before {
  content: "✓";  /* Unicode checkmark */
  color: green;
  position: absolute;
  left: 0;
  font-weight: bold;
}
.fff.checks li::before {color:white}