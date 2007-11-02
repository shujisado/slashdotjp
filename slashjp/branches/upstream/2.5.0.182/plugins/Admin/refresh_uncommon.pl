#!/usr/bin/perl -w

# $Id: refresh_uncommon.pl,v 1.3 2003/08/29 16:18:44 jamie Exp $

use strict;

use Slash::Constants ':slashd';

use vars qw( %task $me );

$task{$me}{timespec} = '50 0,6,12,18 * * *';
$task{$me}{timespec_panic_1} = ''; # if panic, we can wait
$task{$me}{on_startup} = 1;
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	$slashdb->refreshUncommonStoryWords();
};

1;

