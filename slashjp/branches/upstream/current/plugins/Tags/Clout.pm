# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: Clout.pm,v 1.5 2007/11/16 17:21:23 jamiemccarthy Exp $

package Slash::Clout;

use strict;
use warnings;
use Slash;
use Slash::Utility;
use Slash::Tags;
#use Slash::Clout::Describe;
#use Slash::Clout::Vote;
#use Slash::Clout::Moderate;

use base 'Slash::DB::Utility';
use base 'Slash::DB';

use vars qw($VERSION);

($VERSION) = ' $Revision: 1.5 $ ' =~ /\$Revision:\s+([^\s]+)/;

sub init {
	my($self) = @_;

	$self->{months_back} = 4; # default
	my $slashdb = getCurrentDB();
        my $info = $slashdb->getCloutInfo();
        for my $clid (keys %$info) {
                $self->{clid} = $clid if $info->{$clid}{class} eq ref($self);
        }
        warn "cannot find clid for $self" if !$self->{clid};

	my $constants = getCurrentStatic();
	my $tags_reader = getObject('Slash::Tags', { db_type => 'reader' });
	$self->{nodid} = $tags_reader->getTagnameidCreate($constants->{tags_upvote_tagname}   || 'nod');
	$self->{nixid} = $tags_reader->getTagnameidCreate($constants->{tags_downvote_tagname} || 'nix');
	1;
}

1;

