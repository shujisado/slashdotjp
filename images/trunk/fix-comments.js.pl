#!/usr/bin/perl
#
# ad-hoc comments.js fix script for IE

use strict;
use warnings;

my $inq = 0;
my $alt = "";

while (my $l = <>) {
	if (!$inq && $l =~ /^Slash\.Util\.qw\.each\('\\$/) {
		$inq = 1;
	} elsif ($inq && $l =~ /^\}\);$/) {
		$inq = 0;
		print $alt;
	} elsif ($inq && $l =~ /\t(\w+)\s+\\$/) {
		$alt .= "packageObj['$1'] = function(v){if (v===undefined) return $1; $1 = v;}\n";
	} elsif (!$inq) {
		print $l;
	}
}
