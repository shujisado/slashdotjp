#!/usr/bin/perl
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use warnings;

use Slash 2.003;	# require Slash 2.3.x
use Slash::Constants qw(:web);
use Slash::Display;
use Slash::Utility;
use Slash::XML;
use vars qw($VERSION);

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;


sub main {
	my $slashdb   = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();
	my $gSkin     = getCurrentSkin();

	if (! $user->{is_admin}) {
		redirect("$gSkin->{rootdir}/");
		return;
	}

	my %ops = (
		display		=> \&display,
		default		=> \&display
	);

	my $op = $form->{op};
	if (!$op || !exists $ops{$op} || !$ops{$op}[ALLOWED]) {
		$op = 'default';
	}

	header('Console', '', { admin => 1 }) or return;

	$ops{$op}->($slashdb, $constants, $user, $form, $gSkin);

	footer();
}


sub display {
	my($slashdb, $constants, $user, $form, $gSkin) = @_;
	my $remarks   = getObject('Slash::Remarks');
	my $remarkstext = $remarks->displayRemarksTable({ max => 10, print_whole => 1 });

	my $admindb 	= getObject('Slash::Admin');
	my $storyadmin 	= $admindb->showStoryAdminBox("", { updater => 1 });
	my $slashdbox 	= $admindb->showSlashdBox({ updater => 1});
	my $perfbox	= $admindb->showPerformanceBox({ updater => 1});
	my $authorbox	= $admindb->showAuthorActivityBox({updater => 1});


	slashDisplay('display', {
		remarks 	=> $remarkstext,
		storyadmin 	=> $storyadmin,
		slashdbox 	=> $slashdbox,
		perfbox		=> $perfbox,
		authorbox	=> $authorbox
	});

}


createEnvironment();
main();

1;
