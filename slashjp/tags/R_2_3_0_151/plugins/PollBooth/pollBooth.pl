#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2004 by Open Source Development Network. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;

#################################################################
sub main {
	my $slashdb = getCurrentDB();
	my $form = getCurrentForm();
	my $constants = getCurrentStatic();

	my %ops = (
		edit		=> \&editpoll,
		save		=> \&savepoll,
		'delete'	=> \&deletepolls,
		list		=> \&listpolls,
		default		=> \&default,
		vote		=> \&vote,
		vote_return	=> \&vote_return,
		get		=> \&poll_booth,
		preview         => \&editpoll,
		detach		=> \&detachpoll,
		linkstory	=> \&link_story_to_poll
	);

	my $op = $form->{op};
	$op = 'default' unless $ops{$form->{op}};
	if (defined $form->{'aid'} && $form->{'aid'} !~ /^\-?\d$/) {
		undef $form->{'aid'};
	}
# This is unfinished and has been hacked. I don't trust it anymore and
# the site that it was written for does not use it currently -Brian
#
#	# Paranoia is fine, but why can't this be done from the handler 
#	# rather than hacking in special case code? - Cliff
#	if ($op eq "vote_return") {
#		$ops{$op}->($form, $slashdb);
#		# Why not do this in a more generic manner you say? 
#		# Because I am paranoid about this being abused. -Brian
#		#
#		# This doesn't answer my question. How is doing this here
#		# any better or worse than doing it at the end of vote_return()
#		# -Cliff
#		my $SECT = $slashdb->getSection();
#		if ($SECT) {
#			my $url = $SECT->{rootdir} || $constants->{real_rootdir};
#
#			# Remove the scheme and authority portions, if present.
#			$form->{returnto} =~ s{^(?:.+?)?//.+?/}{/};
#			
#			# Form new absolute URL based on section URL and then
#			# redirect the user.
#			my $refer = URI->new_abs($form->{returnto}, $url);
#			redirect($refer->as_string);
#		}
#	}
#
	header(getData('title'), $form->{section}, { tab_selected => 'poll'}) or return;

	$ops{$op}->($form, $slashdb, $constants);

	writeLog($form->{'qid'});
	footer();
}

#################################################################
sub poll_booth {
	my($form) = @_;

	print pollbooth($form->{'qid'}, 0, 1);
}

#################################################################
sub default {
	my($form, $slashdb, $constants) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	if (!$form->{'qid'}) {
		listpolls(@_);
	} elsif (! defined $form->{'aid'}) {
		poll_booth(@_);
	} else {
		my $vote = vote(@_);
		if ($constants->{poll_discussions}) {
			my $discussion_id = $reader->getPollQuestion(
				$form->{'qid'}, 'discussion'
			);
			my $discussion = $reader->getDiscussion($discussion_id)
				if $discussion_id;
			if ($discussion) {
				printComments($discussion);
			}
		}
	}
}

#################################################################
sub link_story_to_poll {
	my($form, $slashdb, $constants) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $qid  = $form->{'qid'};
	my $sid  = $form->{'sid'};
	my $user = getCurrentUser();
	my $min = $form->{min} || 0;
	my $questions = $reader->getPollQuestionList($min);
	

	unless ($user->{'is_admin'}) {
		default(@_);
		return;
	}
	
	# clear current story.qid
	$slashdb->sqlUpdate("stories", { qid=>"" }, "sid = ".$slashdb->sqlQuote($form->{sid}));

	slashDisplay('linkstory', {
		questions	=> $questions,
		startat		=> $min + @$questions,
		admin		=> getCurrentUser('seclev') >= 100,
		title		=> "Link story to poll",
		width		=> '99%',
		sid		=> $sid
	});
}

#################################################################
sub detachpoll {
	my($form, $slashdb, $constants) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $qid  = $form->{'qid'};
	my $sid  = $form->{'sid'};
	my $user = getCurrentUser();
	my $warning;
	

	unless ($user->{'is_admin'}) {
		default(@_);
		return;
	}
	if($sid){
		my $where = "sid=".$slashdb->sqlQuote($sid)." AND qid=".$slashdb->sqlQuote($qid);
		my $count=$slashdb->sqlCount("stories",$where);
		print STDERR "count $count\n";
		if($count){
			$slashdb->sqlUpdate("stories",{ qid => "" } , $where); 
		} elsif ( $form->{force} ){
			$slashdb->sqlUpdate("stories",{ qid => "" } ,"sid=".$slashdb->sqlQuote($sid)); 
		} else {
			$warning->{no_sid_qid_match}=1;
		} 
	} else {
		$warning->{no_sid} = 1;
	}
	
	slashDisplay('detachpoll', {
		title   => "Detaching Poll from Story",
		sid     => $sid,
		qid     => $qid,
		warning => $warning
	});
}

#################################################################
sub editpoll {
	my($form, $slashdb, $constants) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $qid  = $form->{'qid'};
	my $user = getCurrentUser();
	my $warning;

	unless ($user->{'is_admin'}) {
		default(@_);
		return;
	}

	my($question, $answers, $pollbooth, $checked, $story_ref);
	if ($form->{op} eq "preview") {
		foreach (qw/question voters date section topic polltype/) {
			$question->{$_} = $form->{$_};
		}
		
		$story_ref = $reader->sqlSelectHashref("sid,qid,time,section,tid,displaystatus",
			"stories",
			"sid=" . $reader->sqlQuote($form->{sid})
		) if $form->{sid};

		$warning->{invalid_sid} = 1 if $form->{sid} and !$story_ref;

		if ($form->{sid}) {
			if ($form->{qid}) {
				$warning->{attached_to_other} = 1 if $slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0 and qid != ".$slashdb->sqlQuote($form->{qid}));
			} else {
				$warning->{attached_to_other} = 1 if $slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0");
			}
		}

		if ($story_ref) {
			$question->{'date'}	= $story_ref->{'time'};
			$question->{topic}	= $story_ref->{'tid'};
			$question->{section}	= $story_ref->{section};
			$question->{polltype}	= $story_ref->{displaystatus} >= 0 ? "story" : "nodisplay";
		}
                
		$question->{polltype} ||= "section";
 
		my $disp_answers;
		for my $n (1..8) {
			$answers->[$n-1] = [ $form->{"aid$n"}, $form->{"votes$n"} ];
			$disp_answers->[$n-1] = {
				aid	=> $n,
				answer	=> $form->{"aid$n"},
				votes	=> $form->{"votes$n"}
			} if $form->{"aid$n"};
		}
	
		$question->{sid} = $form->{sid};
		$checked = $form->{currentqid};

		my $raw_pollbooth = slashDisplay('pollbooth', {
			qid		=> -1,
			voters		=> $question->{voters},
			poll_open 	=> ($form->{date} le $slashdb->getTime()),
			question	=> $question->{question},
			answers		=> $disp_answers,
			sect		=> $question->{section},
                        has_activated   => 1 
		}, 1);
		$pollbooth = fancybox(
			$constants->{fancyboxwidth}, 
			'Poll', 
			$raw_pollbooth, 
			0, 1
                );
            
        } elsif ($qid) {
		$question = $slashdb->getPollQuestion($qid);
		$question->{sid} = $slashdb->getSidForQID($qid)
			unless $question->{autopoll} eq "yes";
		
		$question->{sid} = $form->{override_sid} if $form->{override_sid};
		
		if ($question->{sid}) {
			$story_ref = $reader->sqlSelectHashref("sid,qid,time,section,tid,displaystatus",
				"stories",
				"sid=" . $reader->sqlQuote($question->{sid})
			);
			if ($story_ref) {
				$question->{'date'}	= $story_ref->{'time'};
				$question->{topic}	= $story_ref->{'tid'};
				$question->{section}	= $story_ref->{section};
				$question->{polltype}	= $story_ref->{displaystatus} >= 0 ? "story" : "nodisplay";
			}
                }
		$question->{polltype} ||= "section";


		$answers = $slashdb->getPollAnswers(
			$qid, [qw( answer votes aid )]
		);
                $question->{polltype} ||= "section";
		$checked = ($slashdb->getSection($question->{section}, 'qid', 1) == $qid) ? 1 : 0;
		my $poll_open = $slashdb->isPollOpen($qid);

		# Just use the DB method, it's too messed up to rebuild the logic
		# here -Brian
		my $poll = $slashdb->getPoll($qid);
		my $raw_pollbooth = slashDisplay('pollbooth', {
			qid		=> $qid,
			voters		=> $question->{voters},
			poll_open 	=> $poll_open,
			question	=> $poll->{pollq}{question},
			answers		=> $poll->{answers},
			voters		=> $poll->{pollq}{voters},
			sect		=> $user->{section} || $question->{section},
                        has_activated   => $slashdb->hasPollActivated($qid)
		}, 1);
		$pollbooth = fancybox(
			$constants->{fancyboxwidth}, 
			'Poll', 
			$raw_pollbooth, 
			0, 1
		);
	}
        

	if ($question) {
		$question->{voters} ||= 0;
	} else {
		$question->{voters} ||= 0;
		$question->{polltype} ||= "section";
		$question->{question} = $form->{question}; 
		$question->{sid} = $form->{sid}; 
	}
 	
	my $date = $question->{date};
        $date ||= $form->{date};
        $date ||= $slashdb->getTime();
        my $topics = $reader->getDescriptions('topics_section');
	slashDisplay('editpoll', {
		title		=> getData('edit_poll_title', { qid=>$qid }),
		qid		=> $qid,
		question	=> $question,
		answers		=> $answers,
		pollbooth	=> $pollbooth,
		checked		=> $checked,
                date		=> $date,
		story		=> $story_ref,
		topics		=> $topics,
		warning		=> $warning
	});
}

#################################################################
sub savepoll {
	my($form, $slashdb, $constants) = @_;

	my $user = getCurrentUser();

	unless ($user->{'is_admin'}) {
		default(@_);
		return;
	}

	if ($form->{question} !~ /\S/) {
		print getData('noquestion');
		editpoll(@_);
		return;
	} else {
		my $q = 0;
		for (my $i = 1; $i < 9; $i++) {
			$q++ if $form->{"aid$i"} =~ /\S/;
		}
		if (!$q) {
			print getData('noanswer');
			editpoll(@_);
			return;
		}
	}
	if ($form->{sid}) {
		if ($form->{qid}) {
			if ($slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0 and qid != ".$slashdb->sqlQuote($form->{qid}))) {
				print getData('attached_to_other');
				editpoll(@_);
				return;
			}
		} else {
			if ($slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0")) {
				print getData('attached_to_other');
				editpoll(@_);
				return;
			}
		}
		if (!$slashdb->sqlCount("stories","sid = ".$slashdb->sqlQuote($form->{sid}))) {
			print getData("invalid_sid");
			editpoll(@_);
			return;
		}
	}

	slashDisplay('savepoll');
	#We are lazy, we just pass along $form as a $poll
	# Correct section for sectional editor first -Brian
	$form->{section} = $user->{section} if $user->{section};
	my $qid = $slashdb->savePollQuestion($form);

	# we have a problem here.  if you attach the poll to an SID,
	# and then unattach it, it will still be attached to that SID
	# until you either change it manually in the DB, or attach it
	# to a new SID.  Deal with it, or send in a patch.  The logic
	# to deal with it otherwise is too complex to be warranted
	# given the infrequency of the circumstance. -- pudge
	# Right - I still need to put a qid editing field into
	# editStory and it'd be nice to see an overall list of which
	# stories are associated with which polls for the last, say,
	# year.  But one thing at a time. -- jamie 2002/04/15

	if ($constants->{poll_discussions}) {
		my $poll = $slashdb->getPollQuestion($qid);
		my $discussion;
		if ($poll->{sid}) {
			# if sid lookup fails, then $discussion is empty,
			# and the poll's discussion is not set
			$discussion = $slashdb->getStory(
				$form->{sid}, 'discussion'
			);
		} elsif (!$poll->{discussion}) {
			$discussion = $slashdb->createDiscussion({
				title		=> $form->{question},
				topic		=> $form->{topic},
				approved	=> 1, # Story discussions are always approved -Brian
				url		=> "$constants->{rootdir}/pollBooth.pl?qid=$qid&aid=-1",
			});
		} elsif ($poll->{discussion}) {
			# Yep, this is lazy -Brian
			$slashdb->setDiscussion($poll->{discussion}, {
				title	=> $form->{question},
				topic	=> $form->{topic}
			});
		}
		# if it already has a discussion (so $discussion is not set),
		# or discussion ID is unchanged, don't bother setting
		$slashdb->setPollQuestion($qid, { discussion => $discussion })
			if $discussion && $discussion != $poll->{discussion};
	}
	$slashdb->setStory($form->{sid}, { qid => $qid }) if $form->{sid};
}

#################################################################
sub vote_return {
	my($form, $slashdb) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	my $qid = $form->{'qid'};
	my $aid = $form->{'aid'};
	return unless $qid && $aid;

	my(%all_aid) = map { ($_->[0], 1) }
		@{$reader->getPollAnswers($qid, ['aid'])};
	my $poll_open = $reader->isPollOpen($qid);
	my $has_voted = $slashdb->hasVotedIn($qid);

	if ($has_voted) {
		# Specific reason why can't vote.
	} elsif (!$poll_open) {
		# Voting is closed on this poll.
	} elsif (exists $all_aid{$aid}) {
		$slashdb->createPollVoter($qid, $aid);
	}
}

#################################################################
sub vote {
	my($form, $slashdb) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });

	my $qid = $form->{'qid'};
	my $aid = $form->{'aid'};
	return unless $qid;

	my(%all_aid) = map { ($_->[0], 1) }
		@{$reader->getPollAnswers($qid, ['aid'])};

	if (! keys %all_aid) {
		print getData('invalid');
		# Non-zero denotes error condition and that comments
		# should not be printed.
		return;
	}

	my $question = $reader->getPollQuestion($qid, ['voters', 'question']);
	my $notes = getData('display');
	if (getCurrentUser('is_anon') && !getCurrentStatic('allow_anon_poll_voting')) {
		$notes = getData('anon');
	} elsif ($aid > 0) {
		my $poll_open = $reader->isPollOpen($qid);
		my $has_voted = $slashdb->hasVotedIn($qid);

		if ($has_voted) {
			# Specific reason why can't vote.
			$notes = getData('uid_voted');
		} elsif (!$poll_open) {
			# Voting is closed on this poll.
			$notes = getData('poll_closed');
		} elsif (exists $all_aid{$aid}) {
			$notes = getData('success', { aid => $aid });
			$slashdb->createPollVoter($qid, $aid);
			$question->{voters}++;
		} else {
			$notes = getData('reject', { aid => $aid });
		}
	}

	my $answers  = $reader->getPollAnswers($qid, ['answer', 'votes']);
	my $maxvotes = $reader->getPollVotesMax($qid);
	my @pollitems;
	for (@$answers) {
		my($answer, $votes) = @$_;
		my $imagewidth	= $maxvotes
			? int(350 * $votes / $maxvotes) + 1
			: 0;
		my $percent	= $question->{voters}
			? int(100 * $votes / $question->{voters})
			: 0;
		push @pollitems, [$answer, $imagewidth, $votes, $percent];
	}

	slashDisplay('vote', {
		qid		=> $qid,
		width		=> '99%',
		title		=> $question->{question},
		voters		=> $question->{voters},
		pollitems	=> \@pollitems,
		notes		=> $notes
	});
}

#################################################################
sub deletepolls {
	my($form) = @_;
	if (getCurrentUser('is_admin')) {
		my $slashdb = getCurrentDB();
		$slashdb->deletePoll($form->{'qid'});
	}
	listpolls(@_);
}

#################################################################
sub listpolls {
	my($form) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $min = $form->{min} || 0;
	my $type = $form->{type};
	my $questions = $reader->getPollQuestionList($min, { type => $type });
	my $sitename = getCurrentStatic('sitename');

	# Just me, but shouldn't title be in the template?
	# yes
	slashDisplay('listpolls', {
		questions	=> $questions,
		startat		=> $min + @$questions,
		admin		=> getCurrentUser('seclev') >= 100,
		title		=> "$sitename Polls",
		width		=> '99%',
                curtime         => $reader->getTime(),
		type		=> $type 
	});
}

#################################################################
createEnvironment();
main();

1;
