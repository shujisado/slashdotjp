#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2003 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;
use Slash::Page;
use Data::Dumper;

sub main {
	my $slashdb	= getCurrentDB();
	my $constants	= getCurrentStatic();
	my $user	= getCurrentUser();
	my $form	= getCurrentForm();
	my $index	= getObject('Slash::Page');

	if ($form->{op} eq 'userlogin' && !$user->{is_anon}) {
		my $refer = $form->{returnto} || $ENV{SCRIPT_NAME};
		redirect($refer);
		return;
	}

	my $section = $slashdb->getSection($form->{section});

	my $title = getData('head', { section => $section->{section} });
	header($title, $section->{section}) or return;
	slashDisplay('index', { 'index' => $index, section => $section->{section} });

	footer();

	writeLog();
}
#################################################################
createEnvironment();
main();

1;
