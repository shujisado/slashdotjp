# $Id: mysql_schema.sql,v 1.2 2008/01/30 22:46:10 jamiemccarthy Exp $

DROP TABLE IF EXISTS uncommonstorywords;
CREATE TABLE uncommonstorywords (
	word VARCHAR(255) NOT NULL,
	PRIMARY KEY (word)
) TYPE=InnoDB;

