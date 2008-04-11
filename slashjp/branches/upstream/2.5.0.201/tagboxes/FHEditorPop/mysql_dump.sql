# $Id: mysql_dump.sql,v 1.4 2008/03/27 01:46:21 jamiemccarthy Exp $
INSERT INTO tagboxes (tbid, name, affected_type, clid, weight, last_run_completed, last_tagid_logged, last_tdid_logged, last_tuid_logged) VALUES (NULL, 'FHEditorPop', 'globj', 2, 1, '2000-01-01 00:00:00', 0, 0, 0);
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_edmult', '10', 'Multiplier by which editor nod/nixes are weighted for editor view');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_udcbasis', '1000', 'Basis for tags_udc vote clout weighting');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_susp_flagpop', '185', 'Admin score to artificially raise a suspicious host item to until an admin tags it');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_susp_maxtaggers', '7', 'Max number of unique users tagging (not voting) a low-scoring firehose item that should not raise suspicion');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_susp_minscore', '100', 'Min score required to not raise suspicion');

