#!/usr/local/bin/perl
# $Id: badge.pl,v 1.1 2007/12/13 15:55:16 scc Exp $

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

sub main {
	my $slashdb = getCurrentDB();
	my $constants = getCurrentStatic();
	my $form = getCurrentForm();
	my $user = getCurrentUser();
	my $gSkin = getCurrentSkin();
	
	my $postflag = $user->{state}{post};
	my $op = $form->{op};

	my $ops = {
		vote => {
			function => \&vote,
			seclev	 => 1,
			post	 => 1
		},

		basic => {
			function => \&forward,
			seclev => 0,
			noheader => 1
		},

		display => {
			function => \&display,
			seclev => 0
		}
	};
	$ops->{default} = $ops->{display};
	$op = 'default' if
		   !$ops->{$op}
		|| !$ops->{$op}{function}
		|| $user->{seclev} < $ops->{$op}{seclev}
		|| !$postflag && $ops->{$op}{post};

	$op = 'basic' if !$form->{op} && !$form->{url};

	if ( !$ops->{$op}{noheader} ) {
		my $r = Apache->request;
		$r->content_type('text/html');
		$r->header_out('Cache-Control', 'no-cache');
		$r->send_http_header;
	}
	
	my $retval = $ops->{$op}{function}->($form, $slashdb, $user, $constants);
}

sub forward {
	my ($form, $slashdb, $user, $constants) = @_;
	my $firehose = getObject('Slash::FireHose');
	my $fh_id = $firehose->getFireHoseIdFromUrl($form->{url});
	my $dest_url = "";
	if ( $fh_id ) {
		$dest_url = "/firehose.pl?op=view&id=${fh_id}";
	} elsif ($form->{url}) {
		# we're about to forward to the submit page, but first: let's note this url as though it were a bookmark

		# copied from plugins/Bookmark/bookmark.pl --- increment or else add a new url
		my $fudgedurl = fudgeurl($form->{url});
		if ( $fudgedurl ) {
			my $url_id = $slashdb->getUrlIfExists($fudgedurl);
			if ( $url_id ) {
				$slashdb->setUrl($url_id, { -anon_bookmarks => 'anon_bookmarks + 1' } );
			} else {
				my $data = {
					initialtitle	=> strip_notags($form->{title}),
					url		=> $fudgedurl,
					anon_bookmarks	=> 1,
				};
				my @allowed_schemes = split(/\|/,$constants->{bookmark_allowed_schemes});
				my %allowed_schemes = map { $_ => 1 } @allowed_schemes;
	
				my $scheme;
				if ($fudgedurl) {
					my $uri = new URI $fudgedurl;
					$scheme = $uri->scheme if $uri && $uri->can("scheme");
				}		
		
				if ($scheme && $allowed_schemes{$scheme}) {
					$slashdb->getUrlCreate($data);
				}
			}
		}

		# ...and _now_ we can head into submit.pl
		my $safe = strip_paramattr($form->{url});
		$dest_url = "/submit.pl?url=${safe}";
	} else {
		$dest_url = "/faq/badges.shtml";
	}
	redirect($dest_url);
}

sub display {
	my ($form, $slashdb, $user, $constants) = @_;
	my $url = $form->{url};
	my $style = 'v0';
	
	if ($form->{style} =~ m/^([hv][01])/i) {
		$style = $1;
	}

	my $firehose = getObject('Slash::FireHose');
	my $fh_id = $firehose->getFireHoseIdFromUrl($form->{url});
	my $voted = '';

	if ( $fh_id && $user->{uid} ) {
		my $fh_item = $firehose->getFireHose($fh_id);
		$voted = $firehose->getUserFireHoseVotesForGlobjs($user->{uid}, [$fh_item->{globjid}])->{$fh_item->{globjid}};
	}

	my $reskey = getObject("Slash::ResKey");
	my $rkey   = $reskey->key('badge_vote_static');
	$rkey->create();

	slashDisplay('main', {
		style => $style,
		url => $url,
		fireHoseId => $fh_id,
		voted => $voted
	}, {Page => 'badge'});
}

sub vote {
	my ($form, $slashdb, $user, $constants) = @_;
	my $firehose = getObject("Slash::FireHose");
	# register vote  && check reskey
	
	my $reskey = getObject('Slash::ResKey');
	my $rkey = $reskey->key('badge_vote_static');
	if ($rkey->use) {
		if ($form->{id} && $form->{dir}) {
			$firehose->firehose_vote($form->{id}, $user->{uid}, $form->{dir});
		}
	} else {
		# error message?
		print STDERR scalar(gmtime) . " Reskey for badge vote failure " . $rkey->errstr . " " . $rkey->failure . "\n";
	}
	display(@_);
}


createEnvironment();
main();

1;
