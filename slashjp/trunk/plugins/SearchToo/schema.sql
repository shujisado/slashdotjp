#
# $Id: schema.sql,v 1.1 2006/09/28 21:42:35 pudge Exp $
#

DROP TABLE IF EXISTS search_index_dump;
CREATE TABLE search_index_dump (
    iid         int UNSIGNED NOT NULL auto_increment,
    id          int UNSIGNED NOT NULL,
    type        VARCHAR(32) DEFAULT '' NOT NULL,
    status      ENUM('new', 'changed', 'deleted') DEFAULT 'new' NOT NULL,
    PRIMARY KEY (iid)
) TYPE=InnoDB;
