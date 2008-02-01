#
# $Id: mysql_schema.sql,v 1.1 2007/06/12 13:21:04 jamiemccarthy Exp $
#

DROP TABLE IF EXISTS firehose_history;
CREATE TABLE firehose_history (
	globjid int UNSIGNED NOT NULL DEFAULT '0',
	secsin int UNSIGNED NOT NULL DEFAULT '0',
	userpop float NOT NULL default '0',
	editorpop float NOT NULL default '0',
	UNIQUE globjid_secsin (globjid, secsin)
) TYPE=InnoDB;

