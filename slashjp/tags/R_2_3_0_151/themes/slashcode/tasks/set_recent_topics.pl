#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2004 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

# This task (and its associated templates and other changes)
# was rewritten almost in its entirety, by Shane Zatezalo
# <shane at lottadot dot com>, May 2002.

use strict;
use Slash::Constants ':slashd';

use vars qw( %task $me );

$task{$me}{timespec} = '1-59/15 * * * *';
$task{$me}{timespec_panic_1} = ''; # not important
$task{$me}{on_startup} = 1;
$task{$me}{code} = sub {

	my($virtual_user, $constants, $slashdb, $user) = @_;

	updateRecentTopics($virtual_user, $constants, $slashdb, $user, '');

	if ($constants->{sections_recenttopics}) {
		for (@{$constants->{sections_recenttopics}}) {
			updateRecentTopics($virtual_user, $constants, $slashdb, $user, $_);
		}
	}

	return ;
};

sub updateRecentTopics {
	my($virtual_user, $constants, $slashdb, $user, $section) = @_;

	my $ar = $slashdb->getNewStoryTopic($section);
        my($html, $num_stories, $cur_tid) = ('', 0);
        my $block = '';
        my $topics = $slashdb->getDescriptions('topics');
        my %tid_list = ( );
        while (my $cur_story = shift @$ar) {
                my $cur_tid = $cur_story->{tid};
		# We only want unique topics to be shown.
		next if exists $tid_list{$cur_story->{tid}};
                $tid_list{$cur_story->{tid}}++;
                ++$num_stories;
                if ($num_stories <= $constants->{recent_topic_img_count}) {
                        if ($cur_story->{image} =~ /^\w+\.\w+$/) {
                                $cur_story->{image} = join("/",
                                        $constants->{imagedir},
                                        "topics",
                                        $cur_story->{image}
                                );
                        }
                        $html .= slashDisplay('setrectop_img', {
                                id      => $cur_tid,
                                image   => $cur_story->{image},
                                width   => $cur_story->{width},
                                height  => $cur_story->{height},
                                alttext => $cur_story->{alttext},
                        }, 1);
                }
                if ($num_stories <= $constants->{recent_topic_txt_count}) {
                        $block .= slashDisplay('setrectop_txt', {
                                id      => $cur_tid,
                                name    => $topics->{$cur_tid},
                        }, 1);
                }
                if ($num_stories >= $constants->{recent_topic_img_count}
                        && $num_stories >= $constants->{recent_topic_txt_count}) {
                        # We're done, no more are needed.
                         last;
                }
        }
        my($tpid) = $slashdb->getTemplateByName('recentTopics', 'tpid', 0, '', $section);
        $slashdb->setTemplate($tpid, { template => $html });
        $slashdb->setBlock('recenttopics', {
                block	=> $block,
                bid	=> 'recenttopics',
        }) unless $section;
}

1;

