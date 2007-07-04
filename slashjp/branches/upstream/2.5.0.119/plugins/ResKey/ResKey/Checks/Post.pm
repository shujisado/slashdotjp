# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: Post.pm,v 1.1 2005/10/24 22:16:02 pudge Exp $

package Slash::ResKey::Checks::Post;

use warnings;
use strict;

use Slash::Utility;
use Slash::Constants ':reskey';

use base 'Slash::ResKey::Key';

our($VERSION) = ' $Revision: 1.1 $ ' =~ /\$Revision:\s+([^\s]+)/;

sub doCheck {
	my($self) = @_;

	return RESKEY_NOOP unless $ENV{GATEWAY_INTERFACE};

	my $user = getCurrentUser();

	if (!$user->{state}{post}) {
		return(RESKEY_FAILURE, ['post method required']);
	}

	return RESKEY_SUCCESS;
}


1;
