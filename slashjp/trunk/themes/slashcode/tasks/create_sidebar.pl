#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2001 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use File::Spec::Functions;
use Slash::Utility;

my $me = 'create_sidebar.pl';

use vars qw( %task );

$task{$me}{timespec} = '8,28,48 * * * *';
$task{$me}{timespec_panic_1} = '5-59/15 * * * *'; # less often
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user) = @_;

	my $nexus_topics = $slashdb->getDescriptions('nexus_topics');
	my $all_topics   = $slashdb->getTopics();
	foreach my $tid (keys(%$nexus_topics)) {
		my $stories = $slashdb->getStoriesEssentials({limit => 10,
							      tid => $tid});
		my $storydata = $slashdb->getStoriesData([map {$_->{stoid}} @$stories]);
		foreach my $story ( @$stories ) {
			$story->{title} = $storydata->{$story->{stoid}}->{title};
		}
		#$topic = $topic ||= 'index';
		open(my $fh, ">$constants->{basedir}/$constants->{sidebardir}/"
		              . $slashdb->getTopic($tid)->{keyword}
			      . ".shtml") || next;
		binmode $fh, ':utf8';
		print $fh slashDisplay('sidebar',
			{ stories => $stories,
			  section => $nexus_topics->{$tid} },
			{ Return => 1 });
		close($fh);
	}
};

1;
