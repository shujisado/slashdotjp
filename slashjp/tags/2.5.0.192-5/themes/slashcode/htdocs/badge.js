(
  function() {
    var url = encodeURIComponent(window.[% sitename %]_url || window.location.href);
    var sty = window.[% sitename %]_badge_style || 'h0';
    var title = encodeURIComponent(window.[% sitename %]_title || document.title);
    var dx=130, dy=25;
    if ( sty[0]=='v' ) {
      dx=52;
      dy=80;
    }
    
    var iframe = '<iframe src="http://[% basedomain %]/badge.pl?style=' + sty + '&url=' + url + '&amp;title=' + title + '"' +
                  ' height="' + dy + '" width="' + dx + '" scrolling="no" frameborder="0"></iframe>'
    document.write(iframe);
  }
)()
