(
  function() {
    var url = encodeURIComponent(window.slashdot_url || window.location.href);
    var sty = window.slashdot_badge_style || 'h0';
    var dx=130, dy=25;
    if ( sty[0]=='v' ) {
      dx=52;
      dy=80;
    }
    
    var iframe = '<iframe src="http://slashdot.jp/slashdot-it.pl?style=' + sty + '&amp;url=' + url + '"' +
                  ' height="' + dy + '" width="' + dx + '" scrolling="no" frameborder="0"></iframe>'
    document.write(iframe);
  }
)()
