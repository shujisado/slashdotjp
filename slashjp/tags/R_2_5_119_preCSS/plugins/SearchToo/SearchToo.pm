package Slash::SearchToo;

use strict;
use Slash::Utility;
use Slash::DB::Utility;
use vars qw($VERSION);
use base 'Slash::DB::Utility';

($VERSION) = ' $Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# FRY: Prepare to be thought at!

#################################################################
sub new {
	my($class, $user, @args) = @_;

	my $constants = getCurrentStatic();
	return unless $constants->{plugin}{'SearchToo'};

	my $api_class = $constants->{search_too_class} || 'Slash::SearchToo::Classic';
	# we COULD do a use base here ... but then different Slash sites
	# cannot use different backends, so hang it -- pudge
	my $self = getObject($api_class, $user, @args);

	if (!$self) {
		warn "Could not get $api_class";
		$self = {};
		bless($self, $class);
		$self->{virtual_user} = $user;
		$self->sqlConnect();
	}

	return $self;
}

#################################################################
# these may be implemeted in backend modules
sub getOps {
	my %ops = (
		comments	=> 1,
		stories		=> 1,
	);
	return \%ops;
}

#################################################################
# these are implemeted only in backend modules
sub findRecords  { warn "findRecords must be implemented in a subclass"; return }
# these are OK to be nonfunctional
sub storeRecords { return }
sub addRecords   { return }
sub prepRecord   { return }
sub getRecords   { return }


#################################################################
# take the results and prepare the data for returning
sub prepResults {
	my($self, $results, $records, $sopts) = @_;

	# two ways of calling
	if (ref $sopts eq 'ARRAY') {
		$sopts = {
			total	=> $sopts->[0],
			matches	=> $sopts->[1],
			start	=> $sopts->[2],
			max	=> $sopts->[3]
		};
	}

	### prepare results
	$records ||= [];
	$results->{records_next}     = 0;
	$results->{records_end}      = scalar @$records
		? ($sopts->{start} + @$records - 1)
		: undef;

	if (defined $sopts->{matches}) {
		$results->{records_next} = $results->{records_end} + 1
			if $sopts->{matches} > $results->{records_end} + 1;
	} else {
		# we added one before; subtract it now
		--$sopts->{max};
		if (@$records >= $sopts->{max}) {
			pop @$records;
			$results->{records_next} = $sopts->{start} + $sopts->{max};
			$results->{records_end}  = $results->{records_next} - 1;
		}
	}

	$results->{records}          = $records;
	$results->{records_returned} = scalar @$records;
	$results->{records_total}    = $sopts->{total};
	$results->{records_matches}  = $sopts->{matches};
	$results->{records_max}      = $sopts->{max};
	$results->{records_start}    = $sopts->{start};

	return $results;
}


#################################################################
# basic processing for common data types
sub _fudge_data {
	my($self, $data) = @_;

	my %processed;

	if ($data->{topic}) {
		my @topics = ref $data->{topic}
			? @{$data->{topic}}
			: $data->{topic};
		$processed{topic} = \@topics;
	} else {
		$processed{topic} = [];
	}

	if ($data->{section}) {
		# make sure we pass a skid
		if ($data->{section} =~ /^\d+$/) {
			$processed{section} = $data->{section};
		} else {
			my $reader = getObject('Slash::DB', { db_type => 'reader' });
			# get section name, for most compatibility with this API
			my $skid = $reader->getSkidFromName($data->{section});
			$processed{section} = $skid if $skid;
		}
	}

	return \%processed;
}


1;

__END__
