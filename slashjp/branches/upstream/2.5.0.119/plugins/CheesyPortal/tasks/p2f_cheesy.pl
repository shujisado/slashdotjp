#!/usr/bin/perl -w

# $Id: p2f_cheesy.pl,v 1.4 2003/08/29 16:18:44 jamie Exp $

use strict;
my $me = 'p2f_cheesy.pl';

use vars qw( %task );

$task{$me}{timespec} = '51 0-23/2 * * *';
$task{$me}{timespec_panic_1} = ''; # not important
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $bd = $constants->{basedir}; # convenience
	for my $name (qw( cheesyportal )) {
		prog2file(
			"$bd/$name.pl", 
			"$bd/$name.shtml", {
				args => "ssi=yes virtual_user=$virtual_user", 
		});
	}

};

