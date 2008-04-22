#!/usr/bin/perl -w

# $Id: clean_blobs.pl,v 1.3 2003/08/29 16:18:44 jamie Exp $

use strict;
use Slash::Constants ':slashd';
use Slash::Display;

use vars qw( %task $me );

# Rewritten
$task{$me}{timespec} = '27 1 * * *';
$task{$me}{timespec_panic_2} = ''; # if major panic, dailyStuff can wait
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;
	my($friends_cache, @deletions);
	my $blob = getObject("Slash::Blob", { db_type => 'writer' });
	$blob->clean();

	return ;
};

1;
