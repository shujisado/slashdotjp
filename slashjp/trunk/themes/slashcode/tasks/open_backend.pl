#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2004 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::XML;
use Slash::Constants ':slashd';

use vars qw( %task $me );

$task{$me}{timespec} = '13,43 * * * *';
$task{$me}{timespec_panic_1} = ''; # not that important
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user, $info) = @_;

	my $backupdb = getObject('Slash::DB', { db_type => 'reader' });

	my $stories = $backupdb->getBackendStories();
	if ($stories && @$stories) {
		newxml(@_, undef, $stories);
		newrdf(@_, undef, $stories);
		#newwml(@_, undef, $stories);
		newrss(@_, undef, $stories);
	}

	my $sections = $backupdb->getDescriptions('sections-all');
	for my $section (keys %$sections) {
		$stories = $backupdb->getBackendStories($section);
		if ($stories && @$stories) {
			newxml(@_, $section, $stories);
			newrdf(@_, $section, $stories);
			newrss(@_, $section, $stories);
		}
	}

	return ;
};

sub save2file {
	my($f, $d) = @_;
	my $fh = gensym();

	# don't rewrite the file if it is has not changed, so clients don't
	# re-FETCH the file; if they send an If-Modified-Since, Apache
	# will just return a header saying the file has not been modified
	# -- pudge
	# on the other hand, don't abort if the file doesn't exist; that
	# probably means the site is newly installed - Jamie 2003/09/05
	if (open $fh, "<$f") {
		my $current = do { local $/; <$fh> };
		close $fh;
		my $new = $d;
		# normalize ...
		s|[dD]ate>[^<]+</|| for $current, $new;
		return if $current eq $new;
	}

	open $fh, ">$f" or die "Can't open $f: $!";
	print $fh $d;
	close $fh;
}

sub _do_rss {
	my($virtual_user, $constants, $backupdb, $user, $info,
		$section, $stories, $version) = @_;

	my $file    = sitename2filename($section);
	my $SECT    = $backupdb->getSection($section);
	my $link    = ($SECT->{url}  || $constants->{absolutedir}) . '/';
	my $title   = $constants->{sitename};
	$title = "$title: $SECT->{title}" if $SECT->{title} ne 'Index';

	my $rss = xmlDisplay('rss', {
		channel		=> {
			title		=> $title,
			'link'		=> $link,
		},
		version		=> $version,
		textinput	=> 1,
		image		=> 1,
		items		=> [ map { { story => $_ } } @$stories ],
	}, 1);

	my $ext = $version == 0.9 ? 'rdf' : 'rss';
	save2file("$constants->{basedir}/$file.$ext", $rss);

}

sub newrdf { _do_rss(@_, "0.9") } # RSS 0.9
sub newrss { _do_rss(@_, "1.0") } # RSS 1.0

sub newwml {
	my($virtual_user, $constants, $backupdb, $user, $info,
		$section, $stories) = @_;

	my $x = <<EOT;
<?xml version="1.0"?>
<!DOCTYPE wml PUBLIC "-//PHONE.COM//DTD WML 1.1//EN" "http://www.phone.com/dtd/wml11.dtd" >
<wml>
                        <head><meta http-equiv="Cache-Control" content="max-age=3600" forua="true"/></head>
<!--  Dev  -->

<!-- TOC -->
<card title="$constants->{sitename}" id="$constants->{sitename}">
<do label="Home" type="options">
<go href="/index.wml"/>
</do>
<p align="left"><b>$constants->{sitename}</b>
<select>
EOT

	my $z = 0;
	my $body;
	for my $sect (@$stories) {
		$x .= qq|<option title="View" onpick="/wml.pl?sid=$sect->{sid}">| .
			xmlencode(strip_notags($sect->{title})) .
			"</option>\n";
		$z++;
	}

	$x .= <<EOT;
</select>
</p>
</card>
</wml>
EOT

	my $file = sitename2filename($section);
	save2file("$constants->{basedir}/$file.wml", $x);
}

sub newxml {
	my($virtual_user, $constants, $backupdb, $user, $info,
		$section, $stories) = @_;

	my $x = <<EOT;
<?xml version="1.0"?><backslash
xmlns:backslash="$constants->{absolutedir}/backslash.dtd">

EOT

	for my $sect (@$stories) {
		my @str = (xmlencode($sect->{title}), xmlencode($sect->{dept}));
		my $author = $backupdb->getAuthor($sect->{uid}, 'nickname');
		$x.= <<EOT;
	<story>
		<title>$str[0]</title>
		<url>$constants->{absolutedir}/article.pl?sid=$sect->{sid}</url>
		<time>$sect->{'time'}</time>
		<author>$author</author>
		<department>$str[1]</department>
		<topic>$sect->{tid}</topic>
		<comments>$sect->{commentcount}</comments>
		<section>$sect->{section}</section>
		<image>$sect->{image}</image>
	</story>

EOT
	}

	$x .= "</backslash>\n";

	my $file = sitename2filename($section);
	save2file("$constants->{basedir}/$file.xml", $x);
}

1;

