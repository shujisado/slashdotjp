# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: Makefile,v 1.9 2005/06/24 13:02:11 jamiemccarthy Exp $

##
##  Makefile -- Plugins Makefile, implements only one target: clean.
##
PLUGINS=`find . -maxdepth 1 -name CVS -prune -o -type d -print | sed 's/^\\.$$//'`

all: clean

clean:
	for a in $(PLUGINS); do \
		(cd $$a; if [ -f Makefile ]; then make clean; fi) \
	done
