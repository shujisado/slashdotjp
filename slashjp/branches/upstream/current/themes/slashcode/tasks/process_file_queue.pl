#!/usr/bin/perl -w
# This code is a part of Slash, and is released under the GPL.
# Copyright 1997-2005 by Open Source Technology Group. See README
# and COPYING for more information, or see http://slashcode.com/.
# $Id: process_file_queue.pl,v 1.2 2007/10/23 20:58:05 tvroom Exp $

use File::Path;
use File::Temp;
use File::Copy;
use Image::Size;
use Slash::Constants ':slashd';

use strict;

use vars qw( %task $me $task_exit_flag );

$task{$me}{timespec} = '* * * * *';
$task{$me}{timespec_panic_1} = '* * * * *';
$task{$me}{timespec_panic_2} = '';
$task{$me}{on_startup} = 1;
$task{$me}{fork} = SLASHD_NOWAIT;
$task{$me}{code} = sub {
	my($virtual_user, $constants, $slashdb, $user, $info, $gSkin) = @_;
	
	my $file_queue_cmds = [];
	my $cmd;
	while (!$task_exit_flag) {
		if(!@$file_queue_cmds) {
			$file_queue_cmds = $slashdb->getNextFileQueueCmds();
		}
		$cmd = shift @$file_queue_cmds;
		if ($cmd->{blobid}) {
			$cmd->{file} = blobToFile($cmd->{blobid});
		}
		if($cmd) {
			handleFileCmd($cmd);
		}
		last if $task_exit_flag;
		sleep(10);
	}
};

sub handleFileCmd {
	my($cmd) = @_;
	my $slashdb = getCurrentDB();
	if ($cmd->{action} eq "thumbnails") {
		slashdLog("Creating Thumbnails");
		my $files = uploadFile($cmd);
		$files ||= [];
		slashdLog("after upload file");
		foreach (@$files) {
			slashdLog("thumbing $_");
			my ($name, $path) = fileparse($_);
			my ($namebase, $suffix) = $name =~ /^(\w+\-\d+)\.(\w+)$/;
			my $thumb = $namebase . "-thumb." . $suffix;
			my $thumbsm = $namebase . "-thumbsm." . $suffix;
			slashdLog("About to create thumb $path$thumb");
			system("convert -size 100x100 $path$name $path$thumb");
			my $data = {
				stoid => $cmd->{stoid},
				name => $thumb
			};
			addStoryFile($data, $path);

			slashdLog("About to create thumbsms $path$thumbsm");
			system("convert -size 50x50 $path$name $path$thumbsm");
			$data = {
				stoid => $cmd->{stoid},
				name => $thumbsm
			};
			addStoryFile($data, $path);
		}
	}
	if ($cmd->{action} eq "upload") {
		slashdLog("handling upload\n");
		uploadFile($cmd);
	}
	$slashdb->deleteFileQueueCmd($cmd->{fqid});
	if (verifyFileLocation($cmd->{file})) {
		unlink $cmd->{file};
	}
}

sub getStoryFileDir {
	my($sid) = @_;
	my $bd = getCurrentStatic("basedir");
	my $yearid  = substr($sid, 0, 2);
	my $monthid = substr($sid, 3, 2);
	my $dayid   = substr($sid, 6, 2);
	my $path = catdir($bd, "images", "articles", $yearid, $monthid, $dayid);
	return $path;
}

sub getFireHoseFileDir {
	my($fhid) = @_;
	my $bd = getCurrentStatic("basedir");
	my ($numdir) = sprintf("%09d",$fhid);
	my ($i,$j) = $numdir =~ /(\d\d\d)(\d\d\d)\d\d\d/;
	my $path = catdir($bd, "images", "firehose", $i, $j);
	return $path;
}

sub makeFileDir {
	my($dir) = @_;
	mkpath $dir, 0, 0775;
}

# verify any file we're copying or deleting meets our expectations
sub verifyFileLocation {
    my($file) = @_;
    return $file =~ /^\/tmp\/upload\/\w+(\.\w+)?$/
}

sub blobToFile {
	my($blobid) = @_;
	my $blob = getObject("Slash::Blob");
	my $blob_ref = $blob->get($blobid);
	my($suffix) = $blob_ref->{filename} =~ /(\.\w+$)/;
	$suffix = lc($suffix);
	my ($ofh, $tmpname) = mkstemps("/tmp/upload/fileXXXXXX", $suffix );
	print $ofh $blob_ref->{data};
	close $ofh;
	return $tmpname;
}

sub uploadFile {
	my($cmd) = @_;
	my @suffixlist = ();
	my $slashdb = getCurrentDB();
	my $story = $slashdb->getStory($cmd->{stoid});
	my @files;

	my $file = $cmd->{file};

	if ($story->{sid}) {
		my $destpath = getStoryFileDir($story->{sid});
		makeFileDir($destpath);
		my ($prefix) = $story->{sid} =~ /^\d\d\/\d\d\/\d\d\/(\d+)$/;
		
		my ($name,$path,$suffix) = fileparse($file,@suffixlist);
	        ($suffix) = $name =~ /(\.\w+)$/;
		if (verifyFileLocation($file)) {
			my $destfile = copyFileToLocation($file, $destpath, $prefix);
			push @files, $destfile if $destfile;
			my $name = fileparse($destfile);
			my $data = {
				stoid => $cmd->{stoid},
				name => $name
			};

			addStoryFile($data, "$destpath/");
		}


	}
	if ($cmd->{fhid}) {
		my $destpath = getFireHoseFileDir($cmd->{fhid});
		makeFileDir($destpath);
		my $numdir = sprintf("%09d",$cmd->{fhid});
		my ($prefix) = $numdir =~ /\d\d\d\d\d\d(\d\d\d)/;
		my $destfile = copyFileToLocation($cmd->{file}, $destpath, $prefix);
		push @files, $destfile if $destfile;
	}
	return \@files;
}

sub copyFileToLocation {
	my ($srcfile,  $destpath, $prefix) = @_;
	slashdLog("$srcfile | $destpath | $prefix\n");
	my @suffixlist;
	my ($name,$path,$suffix) = fileparse($srcfile, @suffixlist);
	($suffix) = $name =~ /(\.\w+)$/;
	$suffix = lc($suffix);
	my $destfile;
	my $foundfile = 0;
	my $i = 1;
	my $ret_val = "";
	while(!$foundfile && $i < 20) {
		$destfile  = $destpath . "/". $prefix . "-$i" . $suffix;
		if (!-e $destfile) {
			$foundfile = 1;
		} else {
			$i++;
		}
	}
	if ($foundfile) {
		copy($srcfile, $destfile);
		$ret_val = $destfile;
	} else {
		slashdLog("Couldn't save file to dir - too many already exist");
	}
	return $ret_val;
}

sub addStoryFile {
	my($data, $path) = @_;
	print "Add story file\n";
	my $slashdb = getCurrentDB();
	slashdLog("addStoryFile $path $data->{name}");
	if ($data->{name} =~ /\.(png|gif|jpg)$/i && $path) {
		($data->{width}, $data->{height}) = imgsize("$path$data->{name}");
		slashdLog("addStoryFile $data->{width} $data->{height}");
	}
	$slashdb->addStoryStaticFile($data);
}

1;
