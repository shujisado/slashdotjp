# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: Makefile,v 1.1 2006/05/17 20:39:57 jamiemccarthy Exp $

##
##  Makefile -- Tagboxes Makefile, implements only one target: clean.
##
TAGBOXES=`find . -maxdepth 1 -name CVS -prune -o -type d -print | sed 's/^\\.$$//'`

all: clean

clean:
	for a in $(TAGBOXES); do \
		(cd $$a; if [ -f Makefile ]; then make clean; fi) \
	done
