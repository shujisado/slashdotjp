#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

use strict;
use Slash;
use Slash::Display;
use Slash::Utility;
use Slash::XML;

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
		get		=> \&poll_booth,
		preview         => \&editpoll,
		detach		=> \&detachpoll,
		linkstory	=> \&link_story_to_poll
	);

        # hijack feeds
	if ($form->{content_type} && $form->{content_type} =~ $constants->{feed_types}) {
		my $mcd = $slashdb->getMCD();
		if ($mcd) {
			my $data = $mcd->get("$slashdb->{_mcd_keyprefix}:xmldcache:$form->{content_type}:pollBooth");
			if ($data->{content}) {
				http_send({
					content_type	=> "application/$form->{content_type}+xml",
					etag		=> ($data->{etag} || undef),
					content		=> $data->{content},
				});
				return 1;
			}
		}
		listpollsRSS($form, $slashdb, $constants);
		return 1;
	}

	my $op = $form->{op} && $ops{$form->{op}} ? $form->{op} : 'default';

	if (defined $form->{aid}) {
		# Only allow a short range of answer ids here.
		# (aid is used as the uid of an author elsewhere
		# in the code, so at least as far as filter_param
		# allows, it can be any integer.)
		$form->{aid} += 0;
		undef $form->{aid} if $form->{aid} < -1 || $form->{aid} > 8;
	}

	# create title
	my $polldb = getObject('Slash::PollBooth', { db_type => 'reader' });
	my $title = getData('title');
	my $meta_desc = '';
	if ($form->{qid}) {
		my $pollq = $polldb->getPollQuestion($form->{qid});
		$title .= ': ' . $pollq->{question};
		$meta_desc = $pollq->{question} . " ";
		my $pollans = $polldb->getPollAnswers($form->{qid}, [ 'answer' ]);
		foreach my $a (@$pollans) {
			$meta_desc .= $a->[0] . "\x{3002}" if ($a->[0]);
		}
	} else {
		my $questions = $polldb->getPollQuestionList(10);
		$meta_desc = '';
		foreach my $q (@$questions) {
			$meta_desc .= $q->[1] . " " if ($q->[1]);
		}
	}
	$meta_desc = shorten(strip_nohtml($meta_desc), 250);
	$title .= " - $constants->{sitename}";

	header($title, $form->{section}, { tab_selected => 'poll', meta_desc => $meta_desc }) or return;

	$ops{$op}->($form, $slashdb, $constants);

	writeLog($form->{'qid'});
	footer();
}

#################################################################
sub poll_booth {
	my($form) = @_;

	slashDisplay('poll', {
		pollbooth	=> pollbooth($form->{'qid'}, 0, 1),
	});
}

#################################################################
sub default {
	my($form, $slashdb, $constants) = @_;
	my $pollbooth_reader = getObject('Slash::PollBooth', { db_type => 'reader' });

	if (!$form->{'qid'}) {
		listpolls(@_);
	} elsif (! defined $form->{'aid'}) {
		poll_booth(@_);
	} else {
		my $vote = vote(@_);
		if ($constants->{poll_discussions}) {
			my $discussion_id = $pollbooth_reader->getPollQuestion(
				$form->{'qid'}, 'discussion'
			);
			my $discussion = $pollbooth_reader->getDiscussion($discussion_id)
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
	my $pollbooth_reader = getObject('Slash::PollBooth', { db_type => 'reader' });
	my $qid  = $form->{'qid'};
	my $sid  = $form->{'sid'};
	my $user = getCurrentUser();
	my $min = $form->{min} || 0;
	my $questions = $pollbooth_reader->getPollQuestionList($min);

	unless ($user->{'is_admin'}) {
		default(@_);
		return;
	}
	
	# clear current story.qid
	# XXX this needs to call setStory_delete_memcached
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
		# XXX this needs to call setStory_delete_memcached
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
	my $pollbooth_db = getObject('Slash::PollBooth');
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
		foreach (qw/question voters date primaryskid topic polltype/) {
			$question->{$_} = $form->{$_};
		}
		
		$story_ref = $reader->sqlSelectHashref("stoid,sid,qid,time,primaryskid,tid",
			"stories",
			"sid=" . $reader->sqlQuote($form->{sid})
		) if $form->{sid};

		$story_ref->{displaystatus} = $reader->_displaystatus($story_ref->{stoid}) if $story_ref;
		
		$warning->{invalid_sid} = 1 if $form->{sid} and !$story_ref;

		if ($form->{sid}) {
			if ($form->{qid}) {
				$warning->{attached_to_other} = 1 if $slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0 and qid != ".$slashdb->sqlQuote($form->{qid}));
			} else {
				$warning->{attached_to_other} = 1 if $slashdb->sqlCount("stories","sid=".$slashdb->sqlQuote($form->{sid})." AND qid > 0");
			}
		}

		if ($story_ref) {
			$question->{'date'}		= $story_ref->{'time'};
			$question->{topic}		= $story_ref->{'tid'};
			$question->{primaryskid}	= $story_ref->{primaryskid};
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
			primaryskid	=> $question->{primaryskid},
                        has_activated   => 1 
		}, 1);
		$pollbooth = fancybox(
			$constants->{fancyboxwidth}, 
			'Poll', 
			$raw_pollbooth, 
			0, 1
                );
            
        } elsif ($qid) {
		$question = $pollbooth_db->getPollQuestion($qid);
		$question->{sid} = $pollbooth_db->getSidForQid($qid)
			unless $question->{autopoll} eq "yes";
		
		$question->{sid} = $form->{override_sid} if $form->{override_sid};
		
		if ($question->{sid}) {
			$story_ref = $reader->sqlSelectHashref("sid,qid,time,primaryskid,tid",
				"stories",
				"sid=" . $reader->sqlQuote($question->{sid})
			);
			
			# XXX I think this is broken, see editpoll template comment - Jamie
			$story_ref->{displaystatus} = $reader->_displaystatus($story_ref->{stoid}) if $story_ref;

			if ($story_ref) {
				$question->{'date'}		= $story_ref->{'time'};
				$question->{topic}		= $story_ref->{'tid'};
				$question->{primaryskid}	= $story_ref->{primaryskid};
				$question->{polltype}	= $story_ref->{displaystatus} >= 0 ? "story" : "nodisplay";
			}
                }
		$question->{polltype} ||= "section";


		$answers = $pollbooth_db->getPollAnswers(
			$qid, [qw( answer votes aid )]
		);
                $question->{polltype} ||= "section";
		my $current_qid = $pollbooth_db->getCurrentQidForSkid($question->{primaryskid});
		$checked = ($current_qid == $qid) ? 1 : 0;
		my $poll_open = $pollbooth_db->isPollOpen($qid);

		# Just use the DB method, it's too messed up to rebuild the logic
		# here -Brian
		my $poll = $pollbooth_db->getPoll($qid);
		my $raw_pollbooth = slashDisplay('pollbooth', {
			qid		=> $qid,
			voters		=> $question->{voters},
			poll_open 	=> $poll_open,
			question	=> $poll->{pollq}{question},
			answers		=> $poll->{answers},
			voters		=> $poll->{pollq}{voters},
			sect		=> $user->{section} || $question->{section},
                        has_activated   => $pollbooth_db->hasPollActivated($qid)
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
        my $topics = $reader->getDescriptions('non_nexus_topics');
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
	my $gSkin = getCurrentSkin();
	my $pollbooth_db = getObject('Slash::PollBooth');

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
	my $qid = $pollbooth_db->savePollQuestion($form);

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
		my $poll = $pollbooth_db->getPollQuestion($qid);
		my $discussion;
		if ($form->{sid}) {
			# if sid lookup fails, then $discussion is empty,
			# and the poll's discussion is not set
			$discussion = $slashdb->getStory(
				$form->{sid}, 'discussion'
			);
		} elsif (!$poll->{discussion}) {
			$discussion = $slashdb->createDiscussion({
				kind		=> 'poll',
				title		=> $form->{question},
				topic		=> $form->{topic},
				approved	=> 1, # Story discussions are always approved -Brian
				url		=> "$gSkin->{rootdir}/polls/$qid?aid=-1",
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
		$pollbooth_db->setPollQuestion($qid, { discussion => $discussion })
			if $discussion && $discussion != $poll->{discussion};
	}
	my $mcd = $slashdb->getMCD();
	if ($mcd) {
		$mcd->delete("$slashdb->{_mcd_keyprefix}:xmldcache:rss:pollBooth", 1);
		$mcd->delete("$slashdb->{_mcd_keyprefix}:xmldcache:atom:pollBooth", 1);
	}
	$slashdb->setStory($form->{sid}, { qid => $qid }) if $form->{sid};
}

#################################################################
sub vote {
	my($form) = @_;
	my $pollbooth_db = getObject('Slash::PollBooth');
	my $pollbooth_reader = getObject('Slash::PollBooth', { db_type => 'reader' });

	my $qid = $form->{'qid'};
	my $aid = $form->{'aid'};
	return unless $qid && $aid;

	my(%all_aid) = map { ($_->[0], 1) }
		@{$pollbooth_reader->getPollAnswers($qid, ['aid'])};

	if (! keys %all_aid) {
		print getData('invalid');
		# Non-zero denotes error condition and that comments
		# should not be printed.
		return;
	}

	my $question = $pollbooth_reader->getPollQuestion($qid, ['voters', 'question']);
	my $notes = getData('display');
	if ($aid > 0) {
		my $poll_open = $pollbooth_reader->isPollOpen($qid);

		if (!$poll_open) {
			# Voting is closed on this poll.
			$notes = getData('poll_closed');
		}

		my $reskey = getObject('Slash::ResKey');
		my $rkey = $reskey->key('pollbooth', { qid => $qid });

		if (!$rkey->createuse) {
			$notes = $rkey->errstr;
		} elsif (exists $all_aid{$aid}) {
			$notes = getData('success', { aid => $aid });
			$pollbooth_db->createPollVoter($qid, $aid);
			$question->{voters}++;
		} else {
			$notes = getData('reject', { aid => $aid });
		}
	}

	my $answers  = $pollbooth_reader->getPollAnswers($qid, ['answer', 'votes']);
	my $maxvotes = $pollbooth_reader->getPollVotesMax($qid);
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
		my $pollbooth_db = getObject('Slash::PollBooth');
		$pollbooth_db->deletePoll($form->{'qid'});
	}
	listpolls(@_);
}

#################################################################
sub listpolls {
	my($form, $slashdb, $constants) = @_;
	my $pollbooth_reader = getObject('Slash::PollBooth', { db_type => 'reader' });
	my $min = $form->{min} || 0;
	my $type = $form->{type};
	my $questions = $pollbooth_reader->getPollQuestionList($min, { type => $type });
	my $gSkin = getCurrentSkin();
	my $opts = ();
	$opts->{type} = $form->{type};
	$opts->{section} = $gSkin->{skid};

	my $section = $gSkin->{name};
	if ($gSkin->{skid} == $constants->{mainpage_skid}) {
		$opts->{section} = '';
	}

	$questions = $pollbooth_reader->getPollQuestionList($min, $opts);

	my $sitename = getCurrentStatic('sitename');

	# Just me, but shouldn't title be in the template?
	# yes
	slashDisplay('listpolls', {
		questions	=> $questions,
		startat		=> $min + @$questions,
		admin		=> getCurrentUser('seclev') >= 100,
		title		=> "$sitename Polls",
		width		=> '99%',
                curtime         => $pollbooth_reader->getTime(),
		type		=> $type 
	});
}

#################################################################
sub listpollsRSS {
	my ($form, $slashdb, $constants) = @_;
	my $polls = getObject('Slash::PollBooth', { db_type => 'reader' });
	my $offset = 0;
	my $limit = 10;

	my $columns = "*";
	my $tables = "pollquestions";
	my $where = "";
	my $other = "ORDER BY date DESC LIMIT $offset, $limit";
	my $questions = $polls->sqlSelectAllHashrefArray($columns, $tables, $where, $other);

	my $items = [];
	foreach my $entry (@$questions) {
		my $poll = $polls->getPoll($entry->{qid});
		my $pollbooth = getData('rss_pollbooth', { poll	=> $poll });
		my $suffix = getData('rss_item_suffix', { poll => $poll });
		push(@$items, {
			story	=> {
				uid	=> $entry->{uid},
				'time'	=> $entry->{date},
			},
			'link'			=> "$constants->{absolutedir}/polls/$entry->{qid}",
			title			=> $entry->{question},
			'time'			=> $entry->{date},
			description		=> $entry->{question} . $suffix,
			'content:encoded'	=> $pollbooth . $suffix,
		});
	}

	xmlDisplay($form->{content_type} => {
		channel			=> {
			title		=> getData('rss_title'),
			description	=> getData('rss_descr'),
			'link'		=> "$constants->{absolutedir}/polls/",
		},
		image			=> 1,
		textinput		=> {
			title	=> getData('search_header_title', { op => getData('polls', {}, 'search') }, 'search'),
			'link'	=> "$constants->{absolutedir}/search.pl?op=polls",
		},
		items			=> $items,
		rdfitemdesc		=> $constants->{dfitemdesc},
		rdfitemdesc_html	=> $constants->{dfitemdesc_html} || 1,
	}, { mcdkey => 'pollBooth' });
}

#################################################################
createEnvironment();
main();

1;
