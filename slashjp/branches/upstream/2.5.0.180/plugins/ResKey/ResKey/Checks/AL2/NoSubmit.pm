# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: NoSubmit.pm,v 1.1 2005/11/08 18:15:02 pudge Exp $

package Slash::ResKey::Checks::AL2::NoSubmit;

use warnings;
use strict;

use Slash::ResKey::Checks::AL2;
use Slash::Utility;
use Slash::Constants ':reskey';

use base 'Slash::ResKey::Key';

our($VERSION) = ' $Revision: 1.1 $ ' =~ /\$Revision:\s+([^\s]+)/;

sub doCheck {
	my($self) = @_;
	return AL2Check($self, 'nosubmit');
}

1;
