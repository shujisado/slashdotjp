# $Id: mysql_dump.sql,v 1.3 2007/09/28 02:47:09 jamiemccarthy Exp $
INSERT INTO tagboxes (tbid, name, affected_type, clid, weight, last_run_completed, last_tagid_logged, last_tdid_logged, last_tuid_logged) VALUES (NULL, 'FHEditorPop', 'globj', 2, 1, '2000-01-01 00:00:00', 0, 0, 0);
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_edmult', '10', 'Multiplier by which editor nod/nixes are weighted for editor view');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_fheditorpop_udcbasis', '1000', 'Basis for tags_udc vote clout weighting');

