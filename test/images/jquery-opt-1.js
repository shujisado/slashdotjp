function firehose_toggle_prefs() {
	if ($("#fh_advprefs").is(":hidden")) {
		$("#fh_advprefs").fadeIn('fast');
	} else {
		$("#fh_advprefs").fadeOut('fast');
	}
	return false;
}


function firehose_init_idle( $new_entries ){

	if($.browser.safari) { /* strage safari bug -- wants to display tags inline only -- cannot replicate in Webkit */
		$('div.tag-display').css('display','list-item !important');
		$('div.tag-display').css('display','inline-block !important');
	}

	/* h1.legend on opera -- not perfect but at least visible */
	if($.browser.opera) {
		$('.tag-display > h1.legend').css({
                                'top':'-30px !important',
                                'left':'70% !important',
                                'position':'relative !important',
                                'float':'left !important'
                });
	}

	if($.browser.safari) {
		$('.vballoon-marquee.rd_5').css('-webkit-border-radius','.5em');
		$('.vballoon-marquee.rd_5 span').css({'margin-top':'1.3em','height':'0.85em'});

		$('.vballoon-firehoselist.rd_5').css('-webkit-border-radius','.5em');
		$('.vballoon-firehoselist.rd_5 span').css({'margin-left':'-.7em','height':'.85em'});

		$('.vbutton.rd_5').css('-webkit-border-radius','.5em');
	}
	if($.browser.mozilla) {
		$('.vballoon-marquee.rd_5').css({
			'border-radius':'.5em',
			'-moz-border-radius':'.5em',
			'margin-top':'-1em'
		});
		$('.vballoon-firehoselist.rd_5').css({
			'border-radius':'.5em',
			'-moz-border-radius':'.5em'
		});
		$('.vbutton.rd_5').css({'border-radius':'.5em','-moz-border-radius':'.5em'});
	}

	/*ff2: attempt to fake anti-aliasing*/
	if ( /^1\.8\.1/.test($.browser.version) ) {
		$('.vballoon-marquee.rd_5').css({
			'border-bottom':'1px solid #004a4a',
			'border-top':'1px solid #004040',
			'border-left':'1px solid #004040',
			'border-right':'1px solid #004040',
			'-moz-border-radius-bottomleft':'.75em',
			'-moz-border-radius-bottomright':'.75em',
			'-moz-border-radius-topleft':'.75em',
			'-moz-border-radius-topright':'.75em',
			'margin-top':'-1em'
		});
		$('.vballoon-marquee.rd_5 span').css('height','1.05em');

		$('.vballoon-firehoselist.rd_5').css({
			border:'1px solid #dedede',
			'-moz-border-radius-bottomleft':'.6em',
			'-moz-border-radius-bottomright':'.65em',
			'-moz-border-radius-topleft':'.5em',
			'-moz-border-radius-topright':'.5em',
			'padding-right':'0.7em'
		});
		$('.vballoon-firehoselist.rd_5 span').css({'height':'0.7em','margin-left':'-0.55em'});

		$('.vbutton.rd_5').css({
			border:'1px solid #dedede',
			'-moz-border-radius':'1em'
		});
	}


	return $new_entries;
}


$(document).ready(function(){
	if($.browser.safari) {
		$(".edit a").css('margin-top','0pt');
	}

	/* h1.legend on opera -- not perfect but at least visible */
	if($.browser.opera) {
                $('.tag-display > h1.legend').css({
                                'top':'-30px !important',
                                'left':'70% !important',
                                'position':'relative !important',
                                'float':'left !important'
                });
	}


      /* This is the hide show on the list */
       /*
	$("#firehose h3 a[class!='skin']").click(function(){
		var $h3 = $(this).parent('h3');
		$h3.next('div.hide').
			add($h3.find('a img')).
				toggle("fast");
		return false;
	}); */

	$("#filter_text").click(function(){
		setTimeout("firehose_slider_init()",500);
		return false;
	});

	$("#slashboxes .block:last-child").prependTo(".head .yui-b").addClass("stats");
	$("#slashboxes .block:first-child").prependTo(".head .yui-b");
	$("#afterwidget span:first-child").css("border","none");

	$(".head .block .content").after("<div class='foot'>&nbsp;</div>");


	$('input[name="nothumbs"]').each( function() {
		if ($(this).attr('checked','checked')) {
			$('#firehose').addClass('vote_enabled');
		} else {
			$('#firehose').removeClass('vote_enabled');
		}
	});

	$('input[name="nocolors"]').each( function() {
		if ($(this).attr('checked','checked')) {
			$('#firehose').addClass('color_enabled');
		} else {
			$('#firehose').removeClass('color_enabled');
		}
	});

	$('.head .tags').appendTo('.head .article .body');

	/* Commenting */
	$('li.comment').parent('ul').parent('li').css('background','none');

	/* This is the nav visual treatment */
	$('#hd div.nav ul li:gt(0)').css('border-left','solid 1px #044');
	$('#ft div.nav ul li:gt(0)').css('border-left','solid 1px #ccc');
	$('#hd div.nav ul li.selected').next('li').css('border-left','none');
	$('#hd div.nav ul li.selected').css('border-left','none');

	/* Fixing slider for div#filter_pref on homepage */
	if($.browser.mozilla || $.browser.opera || $.browser.safari )
		$('#colorsliderthumb').css({
		width:'10px',
		margin:'0',
		left:'-104px',
		top:'5px'
	});




/*
	if($.browser.safari) {
		$('.vbutton.rd_5').css('-webkit-border-radius','.5em');
	}
	if($.browser.mozilla) {
		$('.vbutton.rd_5').css('border-radius','.5em').css('-moz-border-radius','.5em');
	}
	if ( /^1\.8\.1/.test($.browser.version) ) {
		$('.vbutton.rd_5').css({
			border:'1px solid #999',
			'-moz-border-radius-bottomleft':'.65em',
			'-moz-border-radius-bottomright':'.65em',
			'-moz-border-radius-topleft':'.7em',
			'-moz-border-radius-topright':'.7em'
		});
	}
*/








	if($.browser.safari) {
		$('.vballoon-marquee.rd_5').css('-webkit-border-radius','.5em');
		$('.vballoon-marquee.rd_5 span').css({'margin-top':'1.3em','height':'0.85em'});

		$('.vballoon-firehoselist.rd_5').css('-webkit-border-radius','.5em');
		$('.vballoon-firehoselist.rd_5 span').css({'margin-left':'-.7em','height':'.85em'});

		$('.vbutton.rd_5').css('-webkit-border-radius','.5em');
	}
	if($.browser.mozilla) {
		$('.vballoon-marquee.rd_5').css({
			'border-radius':'.5em',
			'-moz-border-radius':'.5em',
			'margin-top':'-1em'
		});
		$('.vballoon-firehoselist.rd_5').css({
			'border-radius':'.5em',
			'-moz-border-radius':'.5em'
		});
		$('.vbutton.rd_5').css({'border-radius':'.5em','-moz-border-radius':'.5em'});
	}

	/*ff2: attempt to fake anti-aliasing*/
	if ( /^1\.8\.1/.test($.browser.version) ) {
		$('.vballoon-marquee.rd_5').css({
			'border-bottom':'1px solid #004a4a',
			'border-top':'1px solid #004040',
			'border-left':'1px solid #004040',
			'border-right':'1px solid #004040',
			'-moz-border-radius-bottomleft':'.75em',
			'-moz-border-radius-bottomright':'.75em',
			'-moz-border-radius-topleft':'.75em',
			'-moz-border-radius-topright':'.75em',
			'margin-top':'-1em'
		});
		$('.vballoon-marquee.rd_5 span').css('height','1.05em');

		$('.vballoon-firehoselist.rd_5').css({
			border:'1px solid #dedede',
			'-moz-border-radius-bottomleft':'.6em',
			'-moz-border-radius-bottomright':'.65em',
			'-moz-border-radius-topleft':'.5em',
			'-moz-border-radius-topright':'.5em',
			'padding-right':'0.7em'
		});
		$('.vballoon-firehoselist.rd_5 span').css({'height':'0.7em','margin-left':'-0.55em'});

		$('.vbutton.rd_5').css({
			border:'1px solid #dedede',
			'-moz-border-radius':'1em'
		});
	}









});

function firehose_marquee(op) {
	if (op == "hide") {
		firehose_set_options('nomarquee', 1);
		$("#marquee a").addClass('collapsed');
		$(".head").hide();
	} else if (op == "show") {
		firehose_set_options('nomarquee', 0);
		$("#marquee a").removeClass('collapsed');
		if($(".head").size()) {
			$(".head").show();
		} else {
			setTimeout("window.location.reload()", "2000");
		}
	}
}

function firehose_slashboxes(op) {
	if (op == "hide") {
		$('.head .block, #slashboxes').fadeOut('fast');
		$('#fad6, #fad2').css('display','none');
		$(this).addClass('collapsed');
		$('.yui-t6 #yui-main .yui-b').css('margin-right','0 !important');
		firehose_set_options('noslashboxes', 1);
	} else if (op == "show") {
		$(this).removeClass('collapsed');
		firehose_set_options('noslashboxes', 0);
		if($('#slashboxes:hidden').size()) {
			$('.head .block, #slashboxes').fadeIn('fast');
			$('#fad6, #fad2').css('display','block');
			$('.yui-t6 #yui-main .yui-b').css('margin-right','336px !important');
		} else {
			setTimeout("window.location.reload()", "2000");
		}
	}
}

