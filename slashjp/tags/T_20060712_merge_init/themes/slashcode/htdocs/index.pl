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
use Time::HiRes;

sub main {
my $start_time = Time::HiRes::time;
	my $constants	= getCurrentStatic();
	my $user	= getCurrentUser();
	my $form	= getCurrentForm();
	my $slashdb	= getCurrentDB();
	my $reader	= getObject('Slash::DB', { db_type => 'reader' });

	if ($form->{op} && $form->{op} eq 'userlogin' && !$user->{is_anon}
			# Any login attempt, successful or not, gets
			# redirected to the homepage, to avoid keeping
			# the password or nickname in the query_string of
			# the URL (this is a security risk via "Referer")
		|| $form->{upasswd} || $form->{unickname}
	) {
		my $refer = $form->{returnto} || $ENV{SCRIPT_NAME};
		redirect($refer); return;
	}

	my($stories, $Stories); # could this be MORE confusing please? kthx

	# why is this commented out?  -- pudge
	# $form->{mode} = $user->{mode} = "dynamic" if $ENV{SCRIPT_NAME};

	# Handle moving a block up or down, or removing it.
	if ($form->{bid} && $form->{op} && $form->{op} =~ /^[udx]$/) {
		   if ($form->{op} eq 'u') { upBid($form->{bid}) }
		elsif ($form->{op} eq 'd') { dnBid($form->{bid}) }
		else                       { rmBid($form->{bid}) }
		redirect($ENV{HTTP_REFERER} || $ENV{SCRIPT_NAME});
		return;
	}

	my $rss = $constants->{rss_allow_index}
		&& $form->{content_type} && $form->{content_type} =~ $constants->{feed_types}
		&& (
			   $user->{is_admin}
			|| ($constants->{rss_allow_index} > 1 && $user->{is_subscriber})
			|| ($constants->{rss_allow_index} > 2 && !$user->{is_anon})
		);

	# $form->{logtoken} is only allowed if using rss
	if ($form->{logtoken} && !$rss) {
		redirect($ENV{SCRIPT_NAME});
	}

	my $skin_name = $form->{section};
	my $skid = $skin_name
		? $reader->getSkidFromName($skin_name)
		: determineCurrentSkin();
	setCurrentSkin($skid);
	my $gSkin = getCurrentSkin();
	$skin_name = $gSkin->{name};

# XXXSKIN I'm turning custom numbers of maxstories off for now, so all
# users get the same number.  This will improve query cache hit rates and 
# right now we need all the edge we can get.  Hopefully we can get this 
# back on soon. - Jamie 2004/07/17
#	my $user_maxstories = $user->{maxstories};
#	my $user_maxstories = getCurrentAnonymousCoward("maxstories");

	# Decide what our issue is going to be.
	my $limit;
	my $issue = $form->{issue} || '';
	$issue = '' if $issue !~ /^\d{8}$/;
#	if ($issue) {
#		if ($user->{is_anon}) {
#			$limit = $gSkin->{artcount_max} * 3;
#		} else {
#			$limit = $user_maxstories * 7;
#		}
#	} elsif ($user->{is_anon}) {
#		$limit = $gSkin->{artcount_max};
#	} else {
#		$limit = $user_maxstories;
#	}

	my $gse_hr = { };
	# Set the characteristics that stories can be in to appear.  This
	# is a simple list:  the current skin's nexus, and then if the
	# current skin is the mainpage, add in the list of story_always_topic
	# and story_always_nexus tids, and story_always_author uids..
	$gse_hr->{tid} = [ $gSkin->{nexus} ];
	if ($gSkin->{skid} == $constants->{mainpage_skid}) {
		my $nexus_children = $reader->getStorypickableNexusChildren($constants->{mainpage_nexus_tid});
		push @{$gse_hr->{tid}}, @$nexus_children;
		
		my @always_tids = split ",",
			$user->{story_always_topic};

		# Let gse know that we're asking for extra tids  beyond those expected by default
		$gse_hr->{tid_extras} = 1 if @always_tids;
		
		push @{$gse_hr->{tid}}, @$nexus_children;
		push @{$gse_hr->{tid}}, @always_tids,
			if @always_tids;
	}
	# Now exclude characteristics.  One tricky thing here is that
	# we never exclude the nexus for the current skin -- if the user
	# went to foo.sitename.com explicitly, then they're going to see
	# stories about foo, regardless of their prefs.  Another tricky
	# thing is that story_never_topic doesn't get used unless a var
	# and/or this user's subscriber status are set a particular way.
	my @never_tids = split /,/, $user->{story_never_nexus};
	if ($constants->{story_never_topic_allow} == 2
		|| ($user->{is_subscriber} && $constants->{story_never_topic_allow} == 1)
	) {
		push @never_tids, split /,/, $user->{story_never_topic};
	}
	@never_tids =
		grep { /^'?\d+'?$/ && $_ != $gSkin->{nexus} }
		@never_tids;
	$gse_hr->{tid_exclude} = [ @never_tids ] if @never_tids;
	$gse_hr->{uid_exclude} = [ split /,/, $user->{story_never_author} ]
		if $user->{story_never_author};

# For now, all users get the same number of maxstories.
#	$gse_hr->{limit} = $user_maxstories if $user_maxstories;

	$gse_hr->{issue} = $issue if $issue;
	if (rand(1) < $constants->{index_gse_backup_prob}) {
		$stories = $reader->getStoriesEssentials($gse_hr);
	} else {
		$stories = $slashdb->getStoriesEssentials($gse_hr);
	}
	
	#my $last_mainpage_view;
	#$last_mainpage_view = $slashdb->getTime() if $gSkin->{nexus} == $constants->{mainpage_skid} && !$user->{is_anon};

#use Data::Dumper;
#print STDERR "index.pl gse_hr: " . Dumper($gse_hr);
#print STDERR "index.pl gSE stories: " . Dumper($stories);

	# We may, in this listing, have a story from the Mysterious Future.
	# If so, there are three possibilities:
	# 1) This user is a subscriber, in which case they see it (and its
	#    timestamp gets altered to the MystFu text)
	# 2) This user is not a subscriber, but is logged-in, and logged-in
	#    non-subscribers are allowed to *know* that there is such a
	#    story without being able to see it, so we make them aware.
	# 3) This user is not a subscriber, and non-subscribers are not
	#    to be made aware of this story's existence, so ignore it.
	my $future_plug = 0;

	# Is there a story in the Mysterious Future?
	my $is_future_story = 0;
	$is_future_story = 1 if @$stories # damn you, autovivification!
		&& $stories->[0]{is_future};

	# Do we want to display the plug saying "there's a future story,
	# subscribe and you can see it"?  Yes if the user is logged-in
	# but not a subscriber, but only if the first story is actually
	# in the future.  If the user has a daypass, they don't get this
	# either.  Just check the first story;  they're in order.
	if ($is_future_story
		&& !$user->{is_subscriber}
		&& !$user->{has_daypass}
		&& !$user->{is_anon}
		&& $constants->{subscribe_future_plug}) {
		$future_plug = 1;
	}

	return do_rss($reader, $constants, $user, $form, $stories, $skin_name) if $rss;

	# Do we want to display the plug offering the user a daypass?
	my $daypass_plug_text = '';
	if ($constants->{daypass}) {
		# If this var is set, only offer a daypass when there
		# is a future story available.
		if (!$constants->{daypass_offer_onlywhentmf}
			|| $is_future_story) {
			my $daypass_db = getObject('Slash::Daypass', { db_type => 'reader' });
			my $do_offer = $daypass_db->doOfferDaypass();
			if ($do_offer) {
				$daypass_plug_text = $daypass_db->getOfferText();
				# On days where a daypass is being offered, for
				# users who are eligible, we give them that
				# message instead of (not in addition to) the
				# "please subscribe" message.
				$future_plug = 0;
			}
		}
	}

#	# See comment in plugins/Journal/journal.pl for its call of
#	# getSkinColors() as well.
#	$user->{currentSection} = $section->{section};
	Slash::Utility::Anchor::getSkinColors();

	# displayStories() pops stories off the front of the @$stories array.
	# Whatever's left is fed to displayStandardBlocks for use in the
	# index_more block (aka Older Stuff).
	# We really should make displayStories() _return_ the leftover
	# stories as well, instead of modifying $stories in place to just
	# suddenly mean something else.
	my $linkrel = {};
	$Stories = displayStories($stories, $linkrel);

	# damn you, autovivification!
	my($first_date, $last_date);
	if (@$stories) {
		($first_date, $last_date) = ($stories->[0]{time}, $stories->[-1]{time});
		$first_date =~ s/(\d\d\d\d)-(\d\d)-(\d\d).*$/$1$2$3/;
		$last_date  =~ s/(\d\d\d\d)-(\d\d)-(\d\d).*$/$1$2$3/;
	}

	my $StandardBlocks = displayStandardBlocks($gSkin, $stories,
		{ first_date => $first_date, last_date => $last_date }
	);

	my $title = getData('head', { skin => $skin_name });
	header({ title => $title, link => $linkrel }) or return;

	if ($form->{remark}
		&& $user->{is_subscriber}
		&& $form->{sid})
	{
		my $sid = $form->{sid};
		my $story = $slashdb->getStory($sid);
		my $remark = $form->{remark};
		# If what's pasted in contains a substring that looks
		# like a sid, yank it out and just use that.
		my $targetsid = getSidFromRemark($remark);
		$remark = $targetsid if $targetsid;
		if ($story) {
			my $remarks = getObject('Slash::Remarks');
			$remarks->createRemark($remark, {
				uid	=> $user->{uid},
				stoid	=> $story->{stoid}
			});
			print getData('remark_thanks');
		}
	}

	slashDisplay('index', {
		metamod_elig	=> scalar $reader->metamodEligible($user),
		future_plug	=> $future_plug,
		daypass_plug_text => $daypass_plug_text,
		stories		=> $Stories,
		boxes		=> $StandardBlocks,
	});

	footer();
	#$slashdb->setUser($user->{uid}, { 'last_mainpage_view' => $last_mainpage_view }) if $last_mainpage_view;
	writeLog($skin_name);

#	{
#		use Proc::ProcessTable;
#		my $t = new Proc::ProcessTable;
#		my $procs = $t->table();
#		PROC: for my $proc (@$procs) {
#			my $pid = $proc->pid();
#			next unless $pid == $$;
#			my $size = $proc->size();
#
#			if ($size > 10_000_000) {
#				my $mb = sprintf("%.2f", $size/1_000_000);
#				print STDERR "pid $$ VSZ $mb MB: just finished op '$form->{op}' sid '$form->{sid}' issue '$form->{issue}' skid '$gSkin->{skid}' uid '$user->{uid}'\n";
#				last PROC;
#			}
#		}
#	}

}


sub getDispModesForStories {
	my($stories, $stories_data_cache, $user, $modes, $story_to_dispmode_hr) = @_;

	my @story_always_topic = split (',', $user->{story_always_topic});
	my @story_always_nexus = split (',', $user->{story_always_nexus});
	my @story_full_brief_nexus = split (',', $user->{story_full_brief_nexus});
	my @story_brief_always_nexus = split (',', $user->{story_brief_always_nexus});
	my @story_full_best_nexus = split (',', $user->{story_full_best_nexus});
	my @story_brief_best_nexus = split (',', $user->{story_brief_best_nexus});

	my(%mp_dispmode_nexus, %sec_dispmode_nexus);
	$mp_dispmode_nexus{$_}  = $modes->[0] foreach (@story_always_nexus, @story_full_brief_nexus, @story_full_best_nexus);
	$mp_dispmode_nexus{$_}  = $modes->[1] foreach (@story_brief_best_nexus, @story_brief_always_nexus);
	$sec_dispmode_nexus{$_} = $modes->[2] foreach (@story_always_nexus);
	$sec_dispmode_nexus{$_} = $modes->[3] foreach (@story_full_brief_nexus, @story_brief_always_nexus);
	$sec_dispmode_nexus{$_} = $modes->[4] foreach (@story_full_best_nexus, @story_brief_best_nexus);

	$story_to_dispmode_hr ||= {};

	# Filter out any story we're planning on skipping up front
	@$stories = grep { getDispModeForStory($_, $stories_data_cache->{$_->{stoid}}, \%mp_dispmode_nexus, \%sec_dispmode_nexus, \@story_always_topic, $story_to_dispmode_hr) ne "none" } @$stories;
}


sub getDispModeForStory {
	my($story, $story_data, $mp_dispmode_nexus_hr, $sec_dispmode_nexus_hr, $always_topic_ar, $dispmode_hr) = @_;
	my $constants = getCurrentStatic();
	my $gSkin     = getCurrentSkin();
	my $slashdb   = getCurrentDB();
	my $skins     = $slashdb->getSkins();
	my $dispmode;

	# sometimes this is uninit ...
	my $ps_nexus = $skins->{$story->{primaryskid}}->{nexus};

	if ($gSkin->{nexus} != $constants->{mainpage_nexus_tid}) {
		$dispmode_hr->{$story->{stoid}} = "full" if $dispmode_hr;
		return "full";
	}

	# XXXNEWINDEX :  Right now we do our best to handle this -- there is no user pref
	# to select whether a user wants to see this in brief vs full mode.  For
	# now we just return "full"  (individual non-nexus topic selection isn't used on
	# Slashdot currently)
	foreach (@$always_topic_ar) {
		$dispmode_hr->{$story->{stoid}} = "full" if $dispmode_hr;
		return "full" if $story_data->{story_topics_rendered}{$_};
	}


	if ($story_data->{story_topics_rendered}{$constants->{mainpage_nexus_tid}}) {
		$dispmode = $mp_dispmode_nexus_hr->{$ps_nexus};
		$dispmode_hr->{$story->{stoid}} = $dispmode if $dispmode_hr && $dispmode;
		return $dispmode if $dispmode;
		$dispmode_hr->{$story->{stoid}} = "full" if $dispmode_hr;
		return "full";
	}

	# Sectional Story -- decide what we should do with it
	$dispmode = $sec_dispmode_nexus_hr->{$ps_nexus};
	$dispmode_hr->{$story->{stoid}} = $dispmode if $dispmode_hr && $dispmode;
	return $dispmode if $dispmode;
	
	# preference for sectional not defined -- go with default for site
	if ($constants->{brief_sectional_mainpage}) {
		$dispmode_hr->{$story->{stoid}} = "brief" if $dispmode_hr;
		return "brief";
	} else {
		$dispmode_hr->{$story->{stoid}} = "none" if $dispmode_hr;
		return "none";
	}
	
}

sub getSidFromRemark {
	my($remark) = @_;
	my $regex = regexSid();
	my($sid) = $remark =~ $regex;
	return $sid || '';
}

sub do_rss {
	my($reader, $constants, $user, $form, $stories, $skin_name) = @_;
	my $gSkin = getCurrentSkin();
	my @rss_stories;

	my @stoids_for_cache =
		map { $_->{stoid} }
		@$stories;
	my $stories_data_cache;
	$stories_data_cache = $reader->getStoriesData(\@stoids_for_cache)
		if @stoids_for_cache;

	getDispModesForStories($stories, $stories_data_cache, $user, [qw(full none full none none)]);


	for (@$stories) {
		my $story = $reader->getStory($_->{sid});
		$story->{introtext} = parseSlashizedLinks($story->{introtext});
		$story->{introtext} = processSlashTags($story->{introtext});
		$story->{introtext} =~ s{(HREF|SRC)\s*=\s*"(//[^/]+)}
		                        {$1 . '="' . url2abs($2)}sieg;
		push @rss_stories, { story => $story };
	}

	my $title = getData('rsshead', { skin => $skin_name });
	my $name = lc($gSkin->{basedomain}) . '.' . $form->{content_type};

	xmlDisplay($form->{content_type} => {
		channel	=> {
			title	=> $title,
		},
		version 		=> $form->{rss_version},
		image			=> 1,
		items			=> \@rss_stories,
		rdfitemdesc		=> 1,
		rdfitemdesc_html	=> 1,
	}, {
		filename		=> $name,
	});

	writeLog($skin_name);
	return;
}

#################################################################
# Should this method be in the DB library?
# absolutely.  we should hide the details there.  but this is in a lot of
# places (modules, index, users); let's come back to it later.  -- pudge
sub saveUserBoxes {
	my(@slashboxes) = @_;
	my $slashdb = getCurrentDB();
	my $user = getCurrentUser();
	return if $user->{is_anon};
	$user->{slashboxes} = join ",", @slashboxes;
	$slashdb->setUser($user->{uid},
		{ slashboxes => $user->{slashboxes} });
}

#################################################################
sub getUserBoxes {
	my $boxes = getCurrentUser('slashboxes');
	$boxes =~ s/'//g;
	return split /,/, $boxes;
}

#################################################################
sub upBid {
	my($bid) = @_;
	my @a = getUserBoxes();
	# Build the %order hash with the order in the values.
	my %order = ( );
	for my $i (0..$#a) {
		$order{$a[$i]} = $i;
	}
	# Reduce the value of the block that's reordered.
	$order{$bid} -= 1.5;
	# Resort back into the new order.
	@a = sort { $order{$a} <=> $order{$b} } keys %order;
	saveUserBoxes(@a);
}

#################################################################
sub dnBid {
	my($bid) = @_;
	my @a = getUserBoxes();
	# Build the %order hash with the order in the values.
	my %order = ( );
	for my $i (0..$#a) {
		$order{$a[$i]} = $i;
	}
	# Increase the value of the block that's reordered.
	$order{$bid} += 1.5;
	# Resort back into the new order.
	@a = sort { $order{$a} <=> $order{$b} } keys %order;
	saveUserBoxes(@a);
}

#################################################################
sub rmBid {
	my($bid) = @_;
	my @a = getUserBoxes();
	@a = grep { $_ ne $bid } @a;
	saveUserBoxes(@a);
}

#################################################################
sub displayStandardBlocks {
	my($skin, $older_stories_essentials, $other) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $user = getCurrentUser();
	my $cache = getCurrentCache();
	my $gSkin = getCurrentSkin();

	return if $user->{noboxes};

	my $return = '';
	my(@boxes, $boxcache);
	my($boxBank, $skinBoxes) = $reader->getPortalsCommon();
	my $getblocks = $skin->{skid} || $constants->{mainpage_skid};

	# two variants of box cache: one for index with portalmap,
	# the other for any other section, or without portalmap

	if ($user->{slashboxes}
		&& ($getblocks == $constants->{mainpage_skid} || $constants->{slashbox_sections})
	) {
		@boxes = getUserBoxes();
		$boxcache = $cache->{slashboxes}{index_map}{$user->{light}} ||= {};
	} else {
		@boxes = @{$skinBoxes->{$getblocks}}
			if ref $skinBoxes->{$getblocks};
		$boxcache = $cache->{slashboxes}{$getblocks}{$user->{light}} ||= {};
	}

	for my $bid (@boxes) {
		next if $user->{lowbandwidth}  && $constants->{lowbandwidth_bids_regex} eq "NONE";
		next if $user->{lowbandwidth} && !($bid =~ $constants->{lowbandwidth_bids_regex} );
		if ($bid eq 'mysite') {
			$return .= portalsidebox(
				getData('userboxhead'),
				$user->{mylinks} || getData('userboxdefault'),
				$bid,
				'',
				$getblocks
			);

		} elsif ($bid =~ /_more$/ && $older_stories_essentials) {
			$return .= portalsidebox(
				getData('morehead'),
				getOlderStories($older_stories_essentials, $skin,
					{ first_date => $other->{first_date}, last_date => $other->{last_date} }),
				$bid,
				'',
				$getblocks,
				'olderstuff'
			) if @$older_stories_essentials;

		} elsif ($bid eq 'userlogin' && ! $user->{is_anon}) {
			# do nothing!

		} elsif ($bid eq 'userlogin' && $user->{is_anon}) {
			$return .= $boxcache->{$bid} ||= portalsidebox(
				$boxBank->{$bid}{title},
				slashDisplay('userlogin', 0, { Return => 1, Nocomm => 1 }),
				$boxBank->{$bid}{bid},
				$boxBank->{$bid}{url},
				$getblocks,
				'login'
			);

		} elsif ($bid eq 'poll' && !$constants->{poll_cache}) {
			# this is only executed if poll is to be dynamic
			$return .= portalsidebox(
				$boxBank->{$bid}{title},
				pollbooth('_currentqid', 1),
				$boxBank->{$bid}{bid},
				$boxBank->{$bid}{url},
				$getblocks
			);
		} elsif ($bid eq 'friends_journal' && $constants->{plugin}{Journal} && $constants->{plugin}{Zoo}) {
			my $journal = getObject("Slash::Journal", { db_type => 'reader' });
			my $zoo = getObject("Slash::Zoo", { db_type => 'reader' });
			my $uids = $zoo->getFriendsUIDs($user->{uid});
			my $articles = $journal->getsByUids($uids, 0,
				$constants->{journal_default_display}, { titles_only => 1 })
				if $uids && @$uids;
			# We only display if the person has friends with data
			if ($articles && @$articles) {
				$return .= portalsidebox(
					getData('friends_journal_head'),
					slashDisplay('friendsview', { articles => $articles}, { Return => 1 }),
					$bid,
					"$gSkin->{rootdir}/my/journal/friends",
					$getblocks
				);
			}
		# this could grab from the cache in the future, perhaps ... ?
		} elsif ($bid eq 'rand' || $bid eq 'srandblock') {
			# don't use cached title/bid/url from getPortalsCommon
			my $data = $reader->getBlock($bid, [qw(title block bid url)]);
			$return .= portalsidebox(
				@{$data}{qw(title block bid url)},
				$getblocks
			);

		} else {
			$boxcache->{$bid} ||= portalsidebox(
				$boxBank->{$bid}{title},
				$reader->getBlock($bid, 'block'),
				$boxBank->{$bid}{bid},
				$boxBank->{$bid}{url},
				$getblocks
			);
			$return .= $boxcache->{$bid};
		}
	}

	return $return;
}

#################################################################
# pass it how many, and what.
sub displayStories {
	my($stories, $linkrel) = @_;
	my $reader = getObject('Slash::DB', { db_type => 'reader' });
	my $constants = getCurrentStatic();
	my $form      = getCurrentForm();
	my $user      = getCurrentUser();
	my $gSkin     = getCurrentSkin();
	my $ls_other  = { user => $user, reader => $reader, constants => $constants };
	my($today, $x) = ('', 0);

	
# XXXSKIN I'm turning custom numbers of maxstories off for now, so all
# users get the same number.  This will improve query cache hit rates and 
# right now we need all the edge we can get.  Hopefully we can get this 
# back on soon. - Jamie 2004/07/17
#       my $user_maxstories = $user->{maxstories};
# Here, maxstories should come from the skin, and $cnt should be
# named minstories and that should come from the skin too.
	my $user_maxstories = getCurrentAnonymousCoward("maxstories");
	my $cnt = $gSkin->{artcount_min};
	my($return, $counter);

	# get some of our constant messages but do it just once instead
	# of for every story
	my $msg;
	$msg->{readmore} = getData('readmore');
	if ($constants->{body_bytes}) {
		$msg->{bytes} = getData('bytes');
	} else {
		$msg->{words} = getData('words');
	}

	# Pull the story data we'll be needing into a cache all at once,
	# to avoid making multiple calls to the DB.
#	my $n_future_stories = scalar grep { $_->{is_future} } @$stories;
#	my $n_for_cache = $cnt + $n_future_stories;
#	$n_for_cache = scalar(@$stories) if $n_for_cache > scalar(@$stories);
	my @stoids_for_cache =
		map { $_->{stoid} }
		@$stories;
#	@stoids_for_cache = @stoids_for_cache[0..$n_for_cache-1]
#		if $#stoids_for_cache > $n_for_cache;
	my $stories_data_cache;
	$stories_data_cache = $reader->getStoriesData(\@stoids_for_cache)
		if @stoids_for_cache;

	my $dispmodelast = "";
	my $story_to_dispmode_hr = {};

	getDispModesForStories($stories, $stories_data_cache, $user, [qw(full brief full brief none)], $story_to_dispmode_hr);

	# Shift them off, so we do not display them in the Older Stuff block
	# later (this simulates the old cursor-based method from circa 1997
	# which was actually not all that smart, but umpteen layers of caching
	# makes it quite tolerable here in 2004 :)
	my $story;
	STORIES_DISPLAY: while ($story = shift @$stories) {
		my($tmpreturn, $other, @links);

		$other->{dispmode} = $story_to_dispmode_hr->{$story->{stoid}};

		# This user may not be authorized to see future stories;  if so,
		# skip them.
		if ($story->{is_future}) {
			# If subscribers are allowed to see 0 seconds into the
			# future, future stories are off-limits.
			next if !$constants->{subscribe_future_secs};
			# If the user is a subscriber or has a daypass, the
			# is_subscriber field will be set.  If that field is
			# not set, future stories are off-limits.
			next if !$user->{is_subscriber} && !$user->{has_daypass};
			# If the user is only an honorary subscriber because
			# they have a daypass, and honorary subscribers don't
			# get to see The Mysterious Future, future stories are
			# off-limits.
			next if !$user->{is_subscriber} && $user->{has_daypass}
				&& !$constants->{daypass_seetmf};
		}

		# Check the day this story was posted (in the user's timezone).
		# Compare it to what we believe "today" is (which will be the
		# first eligible story in this list).  If this story's day is
		# not "today", and if we've already displayed enough stories
		# to sufficiently fill the homepage (typically 10), then we're
		# done -- put the story back on the list (so it'll correctly
		# appear in the Older Stuff box) and exit.
		my $day = timeCalc($story->{time}, '%A %B %d');
		my($w) = join ' ', (split / /, $day)[0 .. 2];
		$today ||= $w;
		if (++$x > $cnt && $today ne $w) {
			unshift @$stories, $story;
			last;
		}

		my @threshComments = split /,/, $story->{hitparade};  # posts in each threshold

		$other->{is_future} = 1 if $story->{is_future};

		#$other->{dispoptions}{new} = 1 if !$user->{is_anon} && $user->{last_mainpage_view} && $gSkin->{nexus} == $constants->{mainpage_skid} && $user->{last_mainpage_view} lt $story->{time};
	
		my $story_data = $stories_data_cache->{$story->{stoid}};
		
		$tmpreturn .= getData("briefarticles_begin")
			if $other->{dispmode} && $other->{dispmode} eq "brief"
				&& $dispmodelast ne "brief";
		$tmpreturn .= getData("briefarticles_end")
			if $dispmodelast eq "brief"
				&& !( $other->{dispmode} && $other->{dispmode} eq "brief" );

		$story->{commentcount} = $threshComments[0] if $story->{commentcount};

		$other->{thresh_commentcount} = $user->{threshold} > -1
			? $threshComments[$user->{threshold} + 1]
			: $story->{commentcount};

		$tmpreturn .= displayStory($story->{sid}, '', $other, $stories_data_cache);
		
		if ($other->{dispmode} eq "full") {
			my $readmore = $msg->{readmore};
			if ($constants->{index_readmore_with_bytes}) {
				my $readmore_data = {};
				if ($story->{body_length}) {
					if ($constants->{body_bytes}) {
						$readmore_data->{bytes} = $story->{body_length};
					} else {
						$readmore_data->{words} = $story->{word_count};
					}
					$readmore = getData('readmore_with_bytes', $readmore_data );
				}
			}

			push @links, linkStory({
				'link'		=> $readmore,
				sid		=> $story->{sid},
				tid		=> $story->{tid},
				skin		=> $story->{primaryskid},
				class		=> 'more'
			}, '', $ls_other);
			my $link;

			if ($constants->{body_bytes}) {
				$link = "$story->{body_length} $msg->{bytes}";
			} else {
				$link = "$story->{word_count} $msg->{words}";
			}
	
			if ($story->{body_length} || $story->{commentcount}) {
				if (!$constants->{index_readmore_with_bytes}) {
					push @links, linkStory({
						'link'		=> $link,
						sid		=> $story->{sid},
						tid		=> $story->{tid},
						mode		=> 'nocomment',
						skin		=> $story->{primaryskid},
					}, '', $ls_other) if $story->{body_length};
				}

				my @commentcount_link;
				my $thresh = $threshComments[$user->{threshold} + 1];

				if ($user->{threshold} > -1 && $story->{commentcount} ne $thresh) {
					$commentcount_link[0] = linkStory({
						sid		=> $story->{sid},
						tid		=> $story->{tid},
						threshold	=> $user->{threshold},
						'link'		=> $thresh,
						skin		=> $story->{primaryskid},
					}, '', $ls_other);
				}

				$commentcount_link[1] = linkStory({
					sid		=> $story->{sid},
					tid		=> $story->{tid},
					threshold	=> -1,
					'link'		=> $story->{commentcount} || 0,
					skin		=> $story->{primaryskid}
				}, '', $ls_other);

				push @commentcount_link, $thresh, ($story->{commentcount} || 0);
				push @links, getData('comments', { cc => \@commentcount_link })
					if $story->{commentcount} || $thresh;
			}

			if ($story->{primaryskid} != $constants->{mainpage_skid} && $gSkin->{skid} == $constants->{mainpage_skid}) {
				my $skin = $reader->getSkin($story->{primaryskid});
				my $url;

				if ($skin->{rootdir}) {
					$url = $skin->{rootdir} . '/';
				} elsif ($user->{is_anon}) {
					$url = $gSkin->{rootdir} . '/' . $story->{name} . '/';
				} else {
					$url = $gSkin->{rootdir} . '/' . $gSkin->{index_handler} . '?section=' . $skin->{name};
				}
	
				push @links, [ $url, $skin->{hostname} || $skin->{title}, '', 'section'];
			}
	
			if ($user->{seclev} >= 100) {
				push @links, [ "$gSkin->{rootdir}/admin.pl?op=edit&sid=$story->{sid}", getData('edit'), '', 'edit' ];
				if ($constants->{plugin}{Ajax}) {
					my $signoff =  slashDisplay("signoff", { stoid => $story->{stoid}, storylink => 1 }, { Return => 1 } ); 
					push @links, $signoff;
				}
			}

			# I added sid so that you could set up replies from the front page -Brian
			$tmpreturn .= slashDisplay('storylink', {
				links	=> \@links,
				sid	=> $story->{sid},
			}, { Return => 1 });

		}

		$return .= $tmpreturn;
		$dispmodelast = $other->{dispmode};
	}
	$return .= getData("briefarticles_end") if $dispmodelast eq "brief";


	unless ($constants->{index_no_prev_next_day}) {
		my($today, $tomorrow, $yesterday, $week_ago) = getOlderDays($form->{issue});
		$return .= slashDisplay('next_prev_issue', {
			today		=> $today,
			tomorrow	=> $tomorrow,
			yesterday	=> $yesterday,
			week_ago	=> $week_ago,
			linkrel		=> $linkrel,
		}, { Return => 1 });
	}
	# limit number of stories leftover for older stories if desired
	$#$stories = ($gSkin->{older_stories_max} - 1) if
		($gSkin->{older_stories_max} < @$stories)
			&&
		($gSkin->{older_stories_max} > 0);

	return $return;

}

#################################################################
createEnvironment();
main();

1;
