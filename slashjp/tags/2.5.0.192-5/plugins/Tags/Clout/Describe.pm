package Slash::Clout::Describe;

use strict;
use warnings;
use Slash::Utility;
use base 'Slash::Clout';

use vars qw($VERSION);

($VERSION) = ' $Revision: $ ' =~ /\$Revision:\s+([^\s]+)/;

sub init {
	my($self) = @_;
	$self->SUPER::init(@_);
	# Hard-coded constants should be in the vars table.
	# cumfrac is the cumulative fraction of how much weight is propagated
	# for each matching tag.  E.g. if $cumfrac is 0.5, the first match may
	# propagate up to 50% of the weight, the second another 25%, the
	# third another 12.5% etc.
	$self->{cumfrac} = 0.5;
	$self->{debug_uids} = { };
	$self->{debug} = 0;
	1;
}

sub getUserClout {
	my($self, $user_stub) = @_;
	my $clout = $user_stub->{karma} >= -3
		? log($user_stub->{karma}+10)
		: 0;
	$clout += 5 if $user_stub->{seclev} > 1;
	$clout *= $user_stub->{tag_clout};
	my $secs_since = time - $user_stub->{created_at_ut};
	my $frac = $secs_since / 30*86400;
	$frac = 0.1 if $frac < 0.1;
	$frac = 1   if $frac > 1;
	$clout *= $frac;
	return $clout;
}

sub get_nextgen {
	my($self, $g) = @_;
	my $tags_reader = getObject('Slash::Tags', { db_type => 'reader' });
	# TODO:
	# - opposite tags. presumably a separate call that joins
	#   sourcetag to newtag via tagnames AS sourcetn and
	#   tagnames AS newtn and (sourcetn.tagname=CONCAT('!', newtn.tagname)
	#   OR newtn.tagname=CONCAT('!', sourcetn.tagname))
	#   except that would be a double table scan I think, ugh
	my $hr_ar = $tags_reader->sqlSelectAllHashrefArray(
		"sourcetag.uid AS sourcetag_uid,
		 UNIX_TIMESTAMP(newtag.created_at)-UNIX_TIMESTAMP(sourcetag.created_at)
			AS timediff,
		 IF(newtag.inactivated IS NULL,
			-1,
			UNIX_TIMESTAMP(newtag.inactivated)-UNIX_TIMESTAMP(newtag.created_at))
			AS duration,
		 newtag.uid AS newtag_uid,
		 users_info.tag_clout AS clout,
		 UNIX_TIMESTAMP(users_info.created_at) AS created_at_ut,
		 karma, tokens,
		 sourcetag.tagnameid,
		 sourcetag.globjid,
		 gtid",
		"tags AS sourcetag,
		 tagname_params AS tagparam,
		 globjs, tags_peerclout AS sourcetpc, users_info,
		 tags AS newtag LEFT JOIN tags_peerclout AS newtpc USING (uid)",
		"sourcetag.inactivated IS NULL
		 AND sourcetag.globjid=globjs.globjid
		 AND sourcetag.uid=sourcetpc.uid
		 AND sourcetpc.clid=$self->{clid}
		 AND sourcetag.globjid=newtag.globjid
		 AND sourcetag.tagnameid=newtag.tagnameid
			AND sourcetag.tagnameid=tagparam.tagnameid
			AND tagparam.name='descriptive'
		 AND sourcetag.tagid != newtag.tagid
		 AND newtag.created_at >= DATE_SUB(NOW(), INTERVAL $self->{months_back} MONTH)
		 AND newtag.uid=users_info.uid
		 AND newtpc.uid IS NULL
		 AND sourcetpc.gen=$g",
		"ORDER BY newtag.tagid");
	return $hr_ar;
}

sub process_nextgen {
	my($self, $hr_ar, $tags_peerclout) = @_;
	my %newtag_uid = ( map { $_->{newtag_uid}, 1 } @$hr_ar );
	my @newtag_uid = sort { $a <=> $b } keys %newtag_uid;

	my $insert_ar = [ ]; my $i = 0;
	for my $newtag_uid (@newtag_uid) {
		my @match = grep { $_->{newtag_uid} == $newtag_uid } @$hr_ar;
		my $match0 = $match[0];
		my($clout, $created_at, $karma, $tokens) =
			($match0->{clout}, $match0->{created_at_ut}, $match0->{karma}, $match0->{tokens});
		if ($self->{debug_uids}{$newtag_uid}) {
			print STDERR ref($self) . sprintf(" starting uid=%d\n", $newtag_uid);
			++$self->{debug};
		}
		my $uid_mults = $self->get_mults(\@match);
		my $weight = $self->get_total_weight($tags_peerclout, $uid_mults, $clout, $created_at, $karma, $tokens);
		push @$insert_ar, {
			uid =>		$newtag_uid,
			clout =>	$weight,
		};
		if ($self->{debug}) {
			use Data::Dumper; my $umd = Dumper($uid_mults); $umd =~ s/\s+/ /g;
			print STDERR ref($self) . " uid=$newtag_uid weight="
				. $self->get_total_weight($tags_peerclout, $uid_mults, $clout, $created_at, $karma, $tokens)
				. " mults: $umd\n";
		}
		++$i;
		if ($i % 100 == 0) {
			print STDERR ref($self) . " process_nextgen processed $i (uid $newtag_uid, matched " . scalar(@match) . ")\n";
		}
		if ($self->{debug_uids}{$newtag_uid}) {
			print STDERR ref($self) . sprintf(" done uid=%d\n", $newtag_uid);
			--$self->{debug};
		}
		Time::HiRes::sleep(0.01);
	}

	return $insert_ar;
}

sub get_mults {
	my($self, $match_ar) = @_;
	my $uid_mults = { };
	for my $hr (@$match_ar) {
		my $mult = $self->get_mult($hr);
		$uid_mults->{ $hr->{sourcetag_uid} } ||= [ ]; 
		push @{$uid_mults->{ $hr->{sourcetag_uid} }}, $mult;
	}
	return $uid_mults;
}

sub get_mult {
	my($self, $hr) = @_;
	
	my $mult = 1.0;
	
	# If the new user's tag was not active for very long, they get no credit.
	# XXX need to check here whether the opposite is in the list, and if
	# so, also no credit. 
	if ($hr->{duration} < 0) {
		# duration of -1 means never inactivated, so full credit.
	} elsif ($hr->{duration} > 3600) {
		$mult = 0.1;
	} else {
		$mult = 0;
	}
	
	# If the new user's tag came before the source user, they get full
	# credit;  too far after the source user, they get reduced credit.
	if ($hr->{timediff} < -3600) {
		$mult *= 1.0;
	} elsif ($hr->{timediff} < 0) {
		$mult *= 0.9;
	} elsif ($hr->{timediff} < 300) {
		$mult *= 0.6;
	} elsif ($hr->{timediff} < 900) {
		$mult *= 0.4;
	} elsif ($hr->{timediff} < 3600) {
		$mult *= 0.1;
	} else {
		$mult *= 0.02;
	}
	
	# Tagging different types gets different mults.
	my $slashdb = getCurrentDB();
	my $type = $slashdb->getGlobjTypes()->{ $hr->{gtid} };
	if ($type eq 'stories') {
		# full credit for matching tags on stories
	} elsif ($type eq 'comments') {
		$mult *= 0.6;
	} else {
		$mult *= 0.7;
	}

	return $mult;
}

sub get_total_weight {
		# uid_mults is a hashref where the key is the source uid and
		# the value is an arrayref of mults from that uid
	my($self, $tags_peerclout, $uid_mults, $clout, $created_at, $karma, $tokens) = @_;

	return 0 if $clout == 0 || $tokens < -1000 || $karma < -10;
		
	my @total_mults = ( );
	
	# Start by sorting source uids by decreasing weight.
my @nodef = grep { !defined $tags_peerclout->{$_} } keys %$uid_mults; $#nodef = 20 if $#nodef > 20; print STDERR "nodef: '@nodef', t_p:" . Dumper($tags_peerclout) if @nodef;
#print STDERR "uid_mults: " . Dumper($uid_mults);
	my @source_uids = sort { $tags_peerclout->{$b} <=> $tags_peerclout->{$a} } keys %$uid_mults;

	# If all source uids have weight 0, we know the answer quickly.
	my $any_weight = 0;
	for my $uid (@source_uids) {
		if ($tags_peerclout->{$uid} > 0) {
			$any_weight = 1;
			last;
		}
	}       
	return 0 if !$any_weight;
			
	# Get the mult for each of those
	for my $uid (@source_uids) {
		my @balanced = $self->balance_weight_vectors(@{$uid_mults->{$uid}});
		push @total_mults, $tags_peerclout->{$uid} * $self->sum_weight_vectors(@balanced);
		if ($self->{debug}) {
			my @tm2 = map { sprintf("%.5g", $_) } @total_mults;
			print STDERR ref($self) . " source_uid=$uid ($tags_peerclout->{$uid}) total_mults='@tm2'\n";
		}       
	}       
			
	# Then (using the same decreasing-multipliers algorithm) get the
	# total of all those mults.
	my @balanced = $self->balance_weight_vectors(@total_mults);
	my $total = $self->sum_weight_vectors(@balanced);
	if ($self->{debug}) {   
		print STDERR ref($self) . " total=$total\n";
	}               
			
	# If this user was created recently, less weight for them.
	my $daysold = (time - $created_at)/86400;
	if ($daysold < 30) {
		$total *= 0.05 * $daysold/30;
	} elsif ($daysold < 90) {
		$total *= 0.3  * $daysold/90;
	} elsif ($daysold < 180) {
		$total *=        $daysold/180;
	}
	
	# If the user has low tokens, less weight for them.
	if ($tokens < -100) {
		$total *= 0.05 * ($tokens+1000)/1000;
	} elsif ($tokens < -10) {
		$total *= 0.6  * ($tokens+100) /100;
	}
	
	# If the user has low karma, less weight for them.
	if ($karma <= 0) {
		$total *= 0.1  * ($karma+10)/10;
	} elsif ($karma < 3) {
		$total *= 0.1;
	} elsif ($karma < 12) {
		$total *= 0.7  * ($karma- 3)/(12- 3);
	} elsif ($karma < 30) {
		$total *= 0.9  * ($karma-12)/(30-12);
	}
	
	# If the user has low clout, less weight for them.
	$total *= $clout;
	
	# If the result is _very_ low, just count it as 0 (this may allow
	# optimizations later).
	$total = 0 if $total < 0.00001;
	
	return $total;
}

sub balance_weight_vectors {
	my($self, @w) = @_;
	@w = sort { abs($b) <=> abs($a) || $b > $a } @w;
	my $w_pos_mag = 0; for my $w (@w) { $w_pos_mag += $w if $w > 0 };
	my $w_neg_mag = 0; for my $w (@w) { $w_neg_mag -= $w if $w < 0 };
	return @w if !$w_pos_mag && !$w_neg_mag;

	my @ret;
	# Swinging more than 60-40% one way or the other reduces the
	# minority's values.
	my $total = $w_pos_mag+$w_neg_mag;
	if ($w_pos_mag > $total * 0.60) {
		my $neg_reduc_factor = $w_neg_mag*3/$w_pos_mag;
		@ret = map { $_ < 0 ? $_*$neg_reduc_factor : $_ } @w;
	} elsif ($w_neg_mag > $total * 0.60) {
		my $pos_reduc_factor = $w_pos_mag*3/$w_neg_mag;
		@ret = map { $_ > 0 ? $_*$pos_reduc_factor : $_ } @w;
	} else {
		# No change.
		@ret = @w;
	}
	if ($self->{debug}) {
		my @w2 = map { sprintf("%5d", @_) } @w;   $#w2 = 4 if $#w2 > 4;
		my @r2 = map { sprintf("%5d", @_) } @ret; $#r2 = 4 if $#r2 > 4;
		print STDERR sprintf("%s balance_weight_vectors pos=%.5g neg=%.5g from '%s' to '%s'\n",
			ref($self), $w_pos_mag, $w_neg_mag, join(' ', @w2), join(' ', @r2));
	}
	return @ret;
}

sub sum_weight_vectors {
	my($self, @v) = @_;
	my @w = sort { abs($b) <=> abs($a) || $b > $a } @v;
	$#w = 50 if $#w > 50; # beyond this point contributions are tiny
	my $weight = 0;
	my $cur_magnitude = 1;
	for my $w (@w) {
		$cur_magnitude *= $self->{cumfrac};
		$weight += $cur_magnitude * $w;
	}
	$weight = 0 if $weight < 0;
	if ($self->{debug}) {
		print STDERR ref($self) . " sum_weight_vectors weight='$weight' w='@w'\n";
	}
	return $weight;
}

sub copy_peerclout_sql {
	my($self) = @_;
	my $slashdb = getCurrentDB();
	$slashdb->sqlDo("SET AUTOCOMMIT=0");
	$slashdb->sqlDo("UPDATE users_clout SET clout=NULL WHERE clid='$self->{clid}'");
	$slashdb->sqlDo("REPLACE INTO users_clout (clout_id, uid, clid, clout) SELECT NULL, uid, '$self->{clid}', clout FROM tags_peerclout WHERE clid='$self->{clid}'");
	$slashdb->sqlDo("COMMIT");
	$slashdb->sqlDo("SET AUTOCOMMIT=1");
}                       

1;

