#!/usr/bin/perl -w
## This code is a part of Slash, and is released under the GPL.
## Copyright 1997-2004 by Open Source Development Network. See README
## and COPYING for more information, or see http://slashcode.com/.
## $Id$

use strict;
use Slash::Constants qw( :messages :slashd );

use vars qw( %task $me );

$task{$me}{timespec} = '23 * * * *';
$task{$me}{timespec_panic_1} = ''; # not important
$task{$me}{on_startup} = 0;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my %data;

	my($now, $lastrun) = updateLastRun($virtual_user, $constants, $slashdb, $user);

	$data{errors} = $slashdb->sqlSelectAllHashref('taskname',
		'COUNT(ts) AS num, taskname, line, errnote, moreinfo',
		'slashd_errnotes',
		"ts BETWEEN '$lastrun' AND '$now'",
		'GROUP BY taskname, line ORDER BY taskname, line');
	my $num_errors = $data{errors} ? scalar(keys %{$data{errors}}) : 0;

# sample dump of $data{errors}:
# $VAR1 = {
#	'run_pdagen.pl' => {
#	       'errnote' => 'error \'65535\' on system() \'/usr/local/slash/site/sitename/sbin/pdaGen.pl slash\'',
#	       'line' => '26',
#	       'moreinfo' => undef,
#	       'num' => '289',
#	       'taskname' => 'run_pdagen.pl'
#	     }
# };

	my $messages = getObject('Slash::Messages');

	if ($messages && $num_errors) {
		$data{template_name} = 'display';
		$data{subject} = 'slashd Error Alert';
		$data{template_page} = 'slashderrnote';
		# shouldn't we loop thru the keys here and create a message
		# for each iteration based on feeding its data to a template
		# or something?
		my $admins = $messages->getMessageUsers(MSG_CODE_ADMINMAIL);
		for my $uid (@$admins) {
			$messages->create($uid, MSG_CODE_ADMINMAIL, \%data);
		}
	}

	return $num_errors;
};

sub updateLastRun {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $lastrun = $slashdb->getVar('slashd_errnote_lastrun', 'value', 1)
		|| '2004-01-01 00:00:00';
	my $now = $slashdb->sqlSelect('NOW()');
	$slashdb->setVar('slashd_errnote_lastrun', $now);

	return($now, $lastrun);
}

1;
