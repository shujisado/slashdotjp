#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash::Utility;

use vars qw( %task $me $task_exit_flag );

$task{$me}{timespec} = '10,40 * * * *';
$task{$me}{timespec_panic_1} = '';
$task{$me}{on_startup} = 1;
$task{$me}{resource_locks} = getCurrentStatic('hc_cepstral') ? { cepstral => 1 } : { };
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $humanconf = getObject('Slash::HumanConf::Static');
	unless ($humanconf) {
		slashdLog("$me: could not instantiate Slash::HumanConf::Static object, is GD.pm properly installed?");
		return ;
	}

	my($deleted, $inserted, $cursize, $hcoff) = (0, 0, 0, '');
	if ($constants->{hc}) {
		$deleted = $humanconf->deleteOldFromPool() || 0;
		return "del $deleted, aborted after deleteOldFromPool" if $task_exit_flag;
		$inserted = $humanconf->fillPool() || 0;
		$cursize = $humanconf->getPoolSize() || 0;
	} else {
		$hcoff = " (hc is off)";
	}

	return "del $deleted, ins $inserted, now $cursize rows$hcoff";
};

1;
