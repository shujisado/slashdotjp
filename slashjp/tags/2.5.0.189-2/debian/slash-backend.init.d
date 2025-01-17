#!/bin/sh
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id$

# /etc/init.d/slash
#
# written by Yazz Atlas for the Slashteam... 
# 	with assists from:
#		Jamie McCarthy
#		Cliff Wood
#		... and a cast of several.

PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin/X11:/usr/X11R6/bin";

# Slash home
PROGNAME="slashd";
DATADIR="/usr/share/slash";
SLASHD="$DATADIR/sbin/$PROGNAME";
SLASHSITE="$DATADIR/slash.sites";
NICE=10

# To figure out where things are...
TZ="GMT";
export TZ;

# load default file
test -f /etc/default/slash && . /etc/default/slash

WHICH_CAT=`which cat`;
WHICH_CUT=`which cut`;
WHICH_PS=`which ps`;
WHICH_GREP=`which grep`;
WHICH_UNAME=`which uname`;
WHICH_AWK=`which awk`;

# if you use sudo, create a file called mysudo in $DATADIR, containing
# your sudo line, like "sudo -u slashdot"
# or "sudo -u foo --shell='/bin/sh'"
MYSUDO=`cat $DATADIR/mysudo 2>/dev/null`

# This prolly ain't 100% accurate, but it should be good enough.
OS=`$WHICH_UNAME | $WHICH_AWK '{print $1}'`;

if [ ! -f $SLASHSITE ] ; then
	echo "[0;31mNOT[1;m Starting $PROGNAME:[0;31m No[1;m $SLASHSITE";
	exit 0;
fi

GRAB_CONFIG=`$WHICH_CAT $SLASHSITE | $WHICH_CUT -d"#" -f1`;

start_slashd () {
	# There are differing syntaxes of "su" between OSes
	# and even between different distributions of the same
	# OS. If you have an OS that isn't listed here (or is
	# a different case of one listed here [ie Red Hat Linux,
	# Debian Linux]) please add in the necessary logic and
	# send in a patch. Thanks!

	# if you aren't using GMT for internal dates, please change
	# the appropriate lines, below.  But why wouldn't you?

	if [ "$MYSUDO" ] ; then
		TZ=GMT $MYSUDO nice -n $NICE $SLASHD $VIRTUAL_USER_NAME
	elif [ "$OS" = "FreeBSD" ] ; then
		TZ=GMT su $USERNAME -c "nice -n $NICE $SLASHD $VIRTUAL_USER_NAME"
	elif [ "$OS" = "Linux" ] ; then 
		su --shell="/bin/sh" - $USERNAME -c "TZ=GMT nice -n $NICE $SLASHD $VIRTUAL_USER_NAME"
	else
		su - $USERNAME -c "TZ=GMT nice -n $NICE $SLASHD $VIRTUAL_USER_NAME"
	fi
}

break_parts () {
	# This is used over and over to break apart the need
	# variables.

	VIRTUAL_USER_NAME=`echo $server_name | $WHICH_CUT -d":" -f1`;
	USERNAME=`echo $server_name | $WHICH_CUT -d":" -f2`;
	SITENAME=`echo $server_name | $WHICH_CUT -d":" -f3`;
	RUNNINGPID="$DATADIR/site/$SITENAME/logs/$PROGNAME.pid";
}

stop_slashd () {
	# This will restart and remove any left over PID files
	# since they can't help anyone. Oh wait, they are useful
	# to verify is slashd is really running. The keepalive
	# choice looks for thoses PID files to see if slashd
	# is hanging about.

	if [ -f $RUNNINGPID ] ; then
		echo -n "Stopping $PROGNAME $VIRTUAL_USER_NAME: ";
		if ! $MYSUDO kill `$WHICH_CAT $RUNNINGPID` ; then
			echo -n "...using kill -9 to make sure ...";
			sleep 3;
			$MYSUDO kill -9 `$WHICH_CAT $RUNNINGPID`;
			$MYSUDO rm -f $RUNNINGPID;
		fi
		echo "ok.";
	else
		echo "$PROGNAME $VIRTUAL_USER_NAME has no PID file";
	fi
}

check_variable () {
	# Just want to print things out so I can see what we are 
	# getting.

	echo "VIRTUAL_USER_NAME=$VIRTUAL_USER_NAME";
	echo "USERNAME=$USERNAME";
	echo "SITENAME=$SITENAME";
	echo "RUNNINGPID=${RUNNINGPID}";
	echo "PID=`cat ${RUNNINGPID}`";
}


# OK now that we set thing above it just matter of calling them in the right
# order. I broke thing up in to functions since I was tired of retyping the 
# same things over and over.

if [ -z "`echo $GRAB_CONFIG | $WHICH_GREP :`" ] ; then
	echo "[0;31mNOT[1;m Starting/stopping $PROGNAME:[0;31m No[1;m sites in $SLASHSITE";
	exit 0;
fi

case "$1" in
	start)
		for server_name in $GRAB_CONFIG; do
			break_parts;
			echo -n "Starting $PROGNAME $VIRTUAL_USER_NAME: ";
			start_slashd;
			sleep 3;
			echo "ok PID = `cat ${RUNNINGPID}`";
		done
		;;

	stop)
		for server_name in $GRAB_CONFIG; do
			break_parts;
			stop_slashd;
		done
		;;

	keepalive)
		for server_name in $GRAB_CONFIG; do
			break_parts;
			if [ ! -f $RUNNINGPID ] ;then
				echo -n "Restarting $PROGNAME $VIRTUAL_USER_NAME, no PID file: ";
				start_slashd;
				sleep 3;
				echo "ok PID = `cat ${RUNNINGPID}`";
			else
				# OK, this might not work on every platform since the "ps"
				# is different on alot of OSes.
				# Once people submit fixes I will pull this into a similar
				# check like the one for "su".
				if ! $WHICH_PS wh -p `$WHICH_CAT $RUNNINGPID` | $WHICH_GREP $PROGNAME > /dev/null ; then
					echo -n "Restarting $PROGNAME $VIRTUAL_USER_NAME, no valid PID file: ";
					rm -f $RUNNINGPID;
					start_slashd;
					sleep 3;
					echo "ok PID = `cat ${RUNNINGPID}`";
				fi
			fi
		done
		;;

	restart|force-reload)
		$0 stop;
		echo -n "Sleeping 10 seconds to be clean: "; 
		sleep 10;
		echo "ok.";
		$0 start;
		;;

	checkvars)
		echo "The contents of $SLASHSITE:";
		for server_name in $GRAB_CONFIG; do
			echo "  $server_name";
		done
		for server_name in $GRAB_CONFIG; do
			echo "";
			break_parts;
			check_variable;
		done
		echo "";
		;;

	*)
		echo "Debian Usage: /etc/init.d/$0 {start|stop|restart|keepalive|checkvars}";
		echo "Redhat Usage: /etc/rc.d/init.d/$0 {start|stop|restart|keepalive|checkvars}";
		echo "Other Usage: /usr/local/sbin/$0 {start|stop|restart|keepalive|checkvars}";
		exit 1;
		;;
esac

exit 0;
