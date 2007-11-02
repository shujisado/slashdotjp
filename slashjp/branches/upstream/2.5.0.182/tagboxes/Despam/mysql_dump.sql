# $Id: mysql_dump.sql,v 1.1 2007/11/01 20:35:18 jamiemccarthy Exp $
INSERT INTO tagboxes (tbid, name, affected_type, clid, weight, last_run_completed, last_tagid_logged, last_tdid_logged, last_tuid_logged) VALUES (NULL, 'Despam', 'globj', 1, 1, '2000-01-01 00:00:00', 0, 0, 0);
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_despam_binspamsallowed', '1', 'Number of binspam tags allowed before action is taken');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_despam_ipdayslookback', '60', 'Number of days to look back in tables to mark IPs, 0 disables IP marking');
INSERT IGNORE INTO vars (name, value, description) VALUES ('tagbox_despam_upvotermaxclout', '0.85', 'Maximum tag_clout for any user who upvotes a submission from a spammer user');
