#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

##################################################################
sub main {
	my $slashdb   = getCurrentDB();
	my $constants = getCurrentStatic();
	my $user      = getCurrentUser();
	my $form      = getCurrentForm();

	my $story;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	my $sid = $form->{sid} || '';
	if ($sid =~ /^\d+$/) {
		# Don't accept a stoid;  we need to be fed a sid to
		# get to the right story.  This prevents crawling
		# through article.pl?sid=1, article.pl?sid=2, etc.
		$sid = '';
	}

	$story = $reader->getStory($sid);
	if ($story && $story->{primaryskid}
		&& !($form->{ssi} && $form->{ssi} eq "yes")) {
		# Make sure the reader is viewing this story in the
		# proper skin.
		my $cur_skid = determineCurrentSkin();
		if ($story->{primaryskid} != $cur_skid) {
			my $cur_skin = $reader->getSkin($cur_skid);
			my $story_skin = $reader->getSkin($story->{primaryskid});
			if ($story_skin && $story_skin->{rootdir}
				&& $story_skin->{rootdir} ne $cur_skin->{rootdir}) {
				redirect("$story_skin->{rootdir}$ENV{REQUEST_URI}");
				return;
			}
		}
	}

	# Set the $future_err flag if a story would be available to be
	# displayed, except it is in the future, and the user is not
	# allowed to see stories in the future.  This is only used to
	# decide what kind of error message to report to the user,
	# later on, if they can't see the story.
	my $future_err = 0;
	if ($story
		&& $story->{is_future} && !$story->{neverdisplay}
		&& !( $user->{is_admin} || $user->{author} || $user->{has_daypass} )
	) {
		$future_err = 1 if !$constants->{subscribe}
			|| !$user->{is_subscriber}
			|| !$user->{state}{page_plummy};
		if ($future_err) {
			$story = '';
		}
	}
	my $stoid = 0;
	$stoid = $story->{stoid} if $story && $story->{stoid};

	# Yeah, I am being lazy and paranoid  -Brian
	# Always check the main DB for story status since it will always be accurate -Brian
	if ($story
		&& !($user->{author} || $user->{is_admin})
		#XXXSECTIONTOPICS verify this is still correct 
		&& !$slashdb->checkStoryViewable($stoid)) {
		$story = '';
	}

	if ($story) {
		# XXXSECTIONTOPICS this needs to be updated
		my $SECT = $reader->getSection($story->{section});
		# This should be a getData call for title
		my $title = "$constants->{sitename} | $story->{title}";

		my $authortext;
		if ($user->{is_admin} ) {
			my $future = $reader->getStoryByTimeAdmin('>', $story, 3);
			$future = [ reverse @$future ];
			my $past = $reader->getStoryByTimeAdmin('<', $story, 3);
			my $current = $reader->getStoryByTimeAdmin('=', $story, 20);
			unshift @$past, @$current;

			$authortext = slashDisplay('futurestorybox', {
				past	=> $past,
				future	=> $future,
			}, { Return => 1 });
		}

		# set things up to use the <LINK> tag in the header
		my %stories;
		my $prev_next_linkrel = '';
		if ($constants->{use_prev_next_link}) {
			# section and series links must be defined as separate
			# constants in vars
			my($use_section, $use_series);
#			$use_section = $story->{section} if
#				$constants->{use_prev_next_link_section} &&
#				$SECT->{type} eq 'contained';
			$use_series  = $story->{tid}     if 
				$constants->{use_prev_next_link_series} &&
				$reader->getTopic($story->{tid})->{series} eq 'yes';

			$stories{'prev'}   = $reader->getStoryByTime('<', $story);
			$stories{'next'}   = $reader->getStoryByTime('>', $story)
				unless $story->{is_future};

			if ($use_section) {
				my @a = ($story, { section => $use_section });
				$stories{'s_prev'} = $reader->getStoryByTime('<', @a);
				$stories{'s_next'} = $reader->getStoryByTime('>', @a)
					unless $story->{is_future};
			}

			if ($use_series) {
				my @a = ($story, { topic => $use_series });
				$stories{'t_prev'} = $reader->getStoryByTime('<', @a);
				$stories{'t_next'} = $reader->getStoryByTime('>', @a)
					unless $story->{is_future};
			}

			# you should only have one next/prev link, so do series first, then sectional,
			# then main, each if applicable -- pudge
			$prev_next_linkrel = $use_series ? 't_' : $use_section ? 's_' : '';
		}

		my $links = {
			title	=> $title,
			story	=> $story,
			'link'	=> {
				section	=> $SECT,
				prev	=> $stories{$prev_next_linkrel . 'prev'},
				'next'	=> $stories{$prev_next_linkrel . 'next'},
				author	=> $story->{uid},
			},
		};

		my $topics = $reader->getStoryTopics($stoid, 1);
		my @topic_desc = values %$topics;
		my $a;
		if (@topic_desc == 1) {
			$a = $topic_desc[0];
		} elsif (@topic_desc == 2){
			$a = join(' and ', @topic_desc);
		} elsif (@topic_desc > 2) {
			my $last = pop @topic_desc;
			$a = join(', ', @topic_desc) . ", and $last";
		}
		my $meta_desc = "$story->{title} -- article related to $a.";

		header($links, $story->{section}, {
			story_title	=> $story->{title},
			meta_desc	=> $meta_desc,
			Page 		=> 'article',
		}) or return;

		# Can't do this before getStoryByTime because
		# $story->{time} is passed to an SQL request.
		$story->{time} = $constants->{subscribe_future_name}
			if $story->{is_future} && !($user->{is_admin} || $user->{author});

		my $pollbooth = pollbooth($story->{qid}, 1)
			if $story->{qid} and ($slashdb->hasPollActivated($story->{qid}) or $user->{is_admin}) ;
		slashDisplay('display', {
			poll			=> $pollbooth,
			section			=> $SECT,
			section_block		=> $reader->getBlock($SECT->{section}),
			show_poll		=> $pollbooth ? 1 : 0,
			story			=> $story,
			authortext		=> $authortext,
			stories			=> \%stories,
		});

		my $called_pc = 0;
		if ($story->{discussion}) {
			# Still not happy with this logic -Brian
			my $discussion = $reader->getDiscussion($story->{discussion});
			$discussion->{is_future} = $story->{is_future} if $discussion;
			if ($constants->{tids_in_urls}) {
				# This is to get tid in comments. It would be a mess to
				# pass it directly to every comment -Brian
				my $tids = $reader->getTopiclistForStory($stoid); 
				my $tid_string = join('&amp;tid=', @$tids);
				$user->{state}{tid} = $tid_string;
			}
			# If no comments ever have existed and commentstatus is disabled,
			# just skip the display of the comment header bar -Brian
			if ($discussion && ! (
				   !$discussion->{commentcount}
				&&  $discussion->{commentstatus} eq 'disabled'
			)) {
				printComments($discussion);
				$called_pc = 1;
			}
		}
		if (!$called_pc && $form->{ssi} && $form->{ssi} eq 'yes' && $form->{cchp}) {
			# This is a real hack, we're kind of skipping down
			# two levels of code.  But the cchp printing is an
			# important optimization;  we avoid having to do
			# multiple expensive comment selects.  One problem
			# is that if there's no discussion with a story,
			# printComments() doesn't get called, which means
			# selectComments() doesn't get called, which means
			# the cchp file won't be written.  If article.pl
			# is being called by slashd, and we need to write
			# that file, then here's where we print an empty
			# file that will satisfy slashd. - Jamie
			Slash::_print_cchp({ stoid => "dummy" });
		}
	} else {
		header('Error', $form->{section}) or return;
		my $message;
		if ($future_err) {
			$message = getData('article_nosubscription');
		} else {
			$message = getData('no_such_sid');
		}
		print $message;
	}

	footer();
	if ($story) {
		writeLog($story->{sid} || $sid);
	} else {
		writeLog($sid);
	}
}

createEnvironment();
main();
1;
