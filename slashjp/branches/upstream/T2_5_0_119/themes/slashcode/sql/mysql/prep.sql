# $Id: prep.sql,v 1.6 2004/06/17 16:12:23 jamiemccarthy Exp $
UPDATE stories SET time = DATE_ADD(NOW(), INTERVAL -2 DAY) WHERE sid = '00/01/25/1430236';
UPDATE stories SET time = DATE_ADD(NOW(), INTERVAL -1 DAY) WHERE sid = '00/01/25/1236215';
UPDATE discussions SET flags = 'hitparade_dirty';
