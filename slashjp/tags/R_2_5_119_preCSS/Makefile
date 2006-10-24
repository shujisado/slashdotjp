# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

##
##  Makefile -- Current one for Slash
##

#   the used tools
VERSION = 2.2.0
DISTNAME = slash
DISTVNAME = $(DISTNAME)-$(VERSION)

CHMOD = chmod
MODE = 0755
SHELL = /bin/sh
PERL = perl
NOOP = $(SHELL) -c true
RM_RF = rm -rf
RM = rm -f
SUFFIX = .gz
COMPRESS = gzip --best
TAR  = tar
SED  = sed
TARFLAGS = cvf
PREOP = @$(NOOP)
POSTOP = @$(NOOP)
TO_UNIX = @$(NOOP)
SLASH_PREFIX = /usr/local/slash
# If this isn't used anymore, can we remove it?
INIT = /etc
USER = nobody
GROUP = nobody
CP = cp
INSTALL = install
UNAME = `uname`
MAKE = make -s

# Subdirectories excl. CVS in the current directory (like plugins/ or tagboxes/)
SUBDIRS = `find . -maxdepth 1 -name CVS -prune -o -type d -name [a-zA-Z]\* -print`

# Perl scripts, grouped by directory.
BINFILES = `find bin -name CVS -prune -o -name [a-zA-Z]\* -type f -print`
SBINFILES = `find sbin -name CVS -prune -o -name [a-zA-Z]\* -type f -print`
THEMEFILES = `find themes -name CVS -prune -o -name [a-zA-z]\*.pl -print`
PLUGINFILES = `find plugins -name CVS -prune -o -name [a-zA-Z]\*.pl -print`
TAGBOXFILES = `find tagboxes -name CVS -prune -o -name [a-zA-Z]\*.pl -print`

# What do we use to invoke perl?
REPLACEWITH = `$(PERL) -MConfig -e 'print quotemeta($$Config{startperl})' | sed 's/@/\\@/g'`

# Scripts that need special treatment for $(SLASH_PREFIX)
PREFIX_REPLACE_FILES = utils/slash httpd/slash.conf

# Used by the RPM build.
BUILDROOT=/var/tmp/slash-buildroot
INSTALLSITEARCH=`$(PERL) -MConfig -e 'print "$(BUILDROOT)/$$Config{installsitearch}"'`
INSTALLSITELIB=`$(PERL) -MConfig -e 'print "$(BUILDROOT)/$$Config{installsitelib}"'`
INSTALLMAN3DIR=`$(PERL) -MConfig -e 'print "$(BUILDROOT)/$$Config{installman3dir}"'`

.PHONY : all plugins tagboxes slash install

#   install the shared object file into Apache 
# We should run a script on the binaries to get the right
# version of perl. 
# I should also grab an install-sh instead of using $(CP)
slash:
	@echo "=== INSTALLING SLASH MODULES ==="
	@if [ ! "$(RPM)" ] ; then \
		(cd Slash; $(PERL) Makefile.PL; $(MAKE) install UNINST=1); \
	else \
		echo " - Performing an RPM build"; \
		(cd Slash; $(PERL) Makefile.PL INSTALLSITEARCH=$(INSTALLSITEARCH) INSTALLSITELIB=$(INSTALLSITELIB) INSTALLMAN3DIR=$(INSTALLMAN3DIR); $(MAKE) install UNINST=1); \
	fi

plugins: 
	@echo "=== INSTALLING SLASH PLUGINS ==="
	@(cd plugins; \
	 for a in $(SUBDIRS); do \
	 	(cd $$a; \
		 echo == $$PWD; \
		 if [ -f Makefile.PL ]; then \
		 	if [ ! "$(RPM)" ] ; then \
				$(PERL) Makefile.PL; \
				$(MAKE) install UNINST=1;\
			else \
				echo " - Performing an RPM build."; \
				$(PERL) Makefile.PL INSTALLSITEARCH=$(INSTALLSITEARCH) INSTALLSITELIB=$(INSTALLSITELIB) INSTALLMAN3DIR=$(INSTALLMAN3DIR); \
				$(MAKE) install UNINST=1; \
			fi; \
		 fi); \
	done)

tagboxes: 
	@echo "=== INSTALLING SLASH TAGBOXES ==="
	@(cd tagboxes; \
	 for a in $(SUBDIRS); do \
	 	(cd $$a; \
		 echo == $$PWD; \
		 if [ -f Makefile.PL ]; then \
		 	if [ ! "$(RPM)" ] ; then \
				$(PERL) Makefile.PL; \
				$(MAKE) install UNINST=1;\
			else \
				echo " - Performing an RPM build."; \
				$(PERL) Makefile.PL INSTALLSITEARCH=$(INSTALLSITEARCH) INSTALLSITELIB=$(INSTALLSITELIB) INSTALLMAN3DIR=$(INSTALLMAN3DIR); \
				$(MAKE) install UNINST=1; \
			fi; \
		 fi); \
	done)

all: install

install: slash plugins tagboxes

	# Create all necessary directories.
	$(INSTALL) -d \
		$(SLASH_PREFIX)/bin/ \
		$(SLASH_PREFIX)/httpd/ \
		$(SLASH_PREFIX)/themes/ \
		$(SLASH_PREFIX)/plugins/ \
		$(SLASH_PREFIX)/tagboxes/ \
		$(SLASH_PREFIX)/sbin \
		$(SLASH_PREFIX)/sql/ \
		$(SLASH_PREFIX)/sql/mysql/

	# Quick hack to avoid the need for "cp -ruv" which breaks under FreeBSD
	# is to just copy the directories now. We may end up copying over a file
	# in the next step that we copy now. To fix this, a major portion of this
	# section of the Makefile would need to be rewritten to do this sanely
	# and there just isn't the time for that right now.
	#
	# Install the plugins and tagboxes.  Will also install kruft like CVS/
	# and blib/ directories if they are around. Maybe a smarter copying
	# procedure is called for, here?)
	# 
	# Note: Many users of Slash have taken to symlinking the plugins and themes
	# directories into $(SLASH_PREFIX) from their checked-out CVS trees. We
	# should try to check for this in the future and behave accordingly.
	# (Update, 2006-05-06: no, we're not going to check for that.  Editing a
	# CVS checkout is great, but push it live with a 'make install' please.)
	#
	# OpenBSD needs "-R" here instead of "-rv".  Its manpage notes:
	# Historic versions of the cp utility had a -r option.  This implementation
	# supports that option; however, its use is strongly discouraged, as it
	# does not correctly copy special files, symbolic links or FIFOs. 
	#
	(cd plugins; $(MAKE) clean) 
	$(CP) -r plugins/* $(SLASH_PREFIX)/plugins
	(cd tagboxes; $(MAKE) clean) 
	$(CP) -r tagboxes/* $(SLASH_PREFIX)/tagboxes
	# Now all the themes
	$(CP) -r themes/* $(SLASH_PREFIX)/themes
	
	# Insure we use the proper Perl interpreter and prefix in all scripts that 
	# we install. Note the use of Perl as opposed to dirname(1) and basename(1)
	# which may or may not exist on any given system.
	(replacewith=$(REPLACEWITH); \
	 binfiles=$(BINFILES); \
	 sbinfiles=$(SBINFILES); \
	 themefiles=$(THEMEFILES); \
	 pluginfiles=$(PLUGINFILES); \
	 tagboxfiles=$(TAGBOXFILES); \
	 if [ "$$replacewith" != "\#\!\/usr\/bin\/perl" ]; then \
	 	replace=1; \
		replacestr='(using $(PERL))'; \
	 else \
	 	replace=0; \
	 fi; \
	 for f in $$binfiles $$sbinfiles $$themefiles $$pluginfiles $$tagboxfiles; do \
		n=$(SLASH_PREFIX)/$$f; \
		$(INSTALL) -d $(SLASH_PREFIX)/$$d; \
	 	if [ $$replace ]; then \
			cat $$f | \
			sed -e "1s/\#\!\/usr\/bin\/perl/$$replacewith/" > $$n.tmp; \
			$(INSTALL) -m $(MODE) $$n.tmp $$n; \
			$(RM) $$n.tmp; \
		else \
			$(INSTALL) $$f $$n; \
		fi; \
	done)

	$(CP) sql/mysql/slashschema_create.sql $(SLASH_PREFIX)/sql/mysql/schema.sql
	$(CP) sql/mysql/defaults.sql $(SLASH_PREFIX)/sql/mysql/defaults.sql

	# This needs BSD support (and Solaris)...
	# ... and the $(SLASH_PREFIX) section is a really ugly hack, too.
	(if [ "$(SLASH_PREFIX)" != "/usr/local/slash" ]; then			\
		replace=1;							\
	 fi;									\
	 for a in $(PREFIX_REPLACE_FILES); do 					\
	 	if [ $$replace ]; then						\
			perl -i.bak -pe 's{/usr/local/slash}{$(SLASH_PREFIX)}' $$a;	\
		fi;								\
		case "$$a" in							\
	 	'utils/slash')							\
			 if [ "$(INIT)" != "/etc" ]; then			\
			 	if [ -d $(INIT) ]; then 		\
			 		init=$(INIT);				\
				fi;								\
			 elif [ -d /etc/init.d ]; then 				\
	 			init=/etc;					\
			 elif [ -d /etc/rc.d/init.d ]; then 			\
		 		init=/etc/rc.d;					\
			 fi;							\
			 if [ $$init ]; then					\
 			 	$(INSTALL) utils/slash $$init/init.d/;		\
				ln -s -f ../init.d/slash $$init/rc3.d/S99slash;	\
				ln -s -f ../init.d/slash $$init/rc6.d/K99slash;	\
			 else 							\
				echo "*** Makefile can't determine where your init scripts live."; \
				if [ $$init ]; then				\
					echo "***   ('$(INIT)' does not exist)";	\
				fi;						\
				echo "*** You will need to look at how to install utils/slashd"; \
				echo "*** on your own.";			\
			 fi;							\
			 ;;							\
		'httpd/slash.conf')						\
			if [ -f $(SLASH_PREFIX)/httpd/slash.conf ]; then	\
				echo "Preserving old slash.conf"; 		\
			else 							\
				$(CP) httpd/slash.conf $(SLASH_PREFIX)/httpd/slash.conf; \
			fi;							\
			$(CP) httpd/slash.conf $(SLASH_PREFIX)/httpd/slash.conf.def; \
			;;							\
		esac;								\
		if [ $$replace ]; then						\
	 		mv $$a.bak $$a;	 					\
		fi;								\
	done)
	# Remove any kruft thay may have been copied that shouldn't have been.
	# Normally we save some time by not diving into an installed site's
	# htdocs' archived directories, but apparently Sun's "find" doesn't
	# support "-path" so skip it.
	if [ $(UNAME) != "SunOS" ]; then					\
	find $(SLASH_PREFIX)							\
		\( -type d -a -path */site/*/htdocs*/[0-9][0-9]* -a -prune \)	\
		-o								\
		\( -name CVS -type d   -o   -name .#* -type f \)		\
			-a \( -prune						\
				-exec $(RM_RF) {} \; \)				\
		2> /dev/null ;							\
	else									\
	find $(SLASH_PREFIX)							\
		\( -name CVS -type d   -o   -name .#* -type f \)		\
			-a \( -prune						\
				-exec $(RM_RF) {} \; \)				\
		2> /dev/null ;							\
	fi

	touch $(SLASH_PREFIX)/slash.sites
	chown $(USER):$(GROUP) $(SLASH_PREFIX)
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/themes
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/sbin
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/bin
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/sql
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/plugins
	chown -R $(USER):$(GROUP) $(SLASH_PREFIX)/tagboxes
# Add a @ to suppress output of the echo's
	@echo "+--------------------------------------------------------+"; \
	echo "| All done.                                              |"; \
	echo "| If you want to let Slash handle your httpd.conf file   |"; \
	echo "| go add:                                                |"; \
	echo "|                                                        |"; \
	echo "| Include $(SLASH_PREFIX)/httpd/slash.conf              |"; \
	echo "|                                                        |"; \
	echo "| to your httpd.conf for apache.                         |"; \
	echo "| If not, cat its content into your httpd.conf file.     |"; \
	echo "|                                                        |"; \
	echo "| Thanks for installing Slash.                           |"; \
	echo "+--------------------------------------------------------+"; \

reload: install
	apachectl stop
	apachectl start

#   cleanup
clean:
	(cd Slash; if [ ! -f Makefile ]; then perl Makefile.PL; fi; $(MAKE) clean)
	(rm Slash/Apache/Apache.xs Slash/Apache/User/User.xs)
	(cd plugins; $(MAKE) clean)
	(cd tagboxes; $(MAKE) clean)
	find ./ | grep \# | xargs rm

dist: $(DISTVNAME).tar$(SUFFIX)

$(DISTVNAME).tar$(SUFFIX) : distdir
	$(PREOP)
	$(TO_UNIX)
	$(TAR) $(TARFLAGS) $(DISTVNAME).tar $(DISTVNAME)
	$(RM_RF) $(DISTVNAME)
	$(COMPRESS) $(DISTVNAME).tar
	$(POSTOP)

distdir :
	$(RM_RF) $(DISTVNAME)
	$(PERL) -MExtUtils::Manifest=manicopy,maniread \
	-e "manicopy(maniread(),'$(DISTVNAME)', '$(DIST_CP)');"

manifest :
	(cd Slash; $(MAKE) distclean)
	$(PERL) -MExtUtils::Manifest -e 'ExtUtils::Manifest::mkmanifest'

rpm :
	rpm -ba slash.spec

