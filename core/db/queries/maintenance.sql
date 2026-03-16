-- ============================================================
-- MAINTENANCE QUERIES — periodic cleanup and health checks
-- ============================================================

-- 1. Flag stale decisions (referenced domain/files changed significantly)
-- Run periodically or at workflow start
UPDATE decisions SET status = 'stale'
WHERE status = 'active'
AND id IN (
    SELECT d.id FROM decisions d
    WHERE NOT EXISTS (
        SELECT 1 FROM changes c
        WHERE c.file_path LIKE '%' || d.domain || '%'
        AND c.created_at > d.created_at
    )
    AND d.created_at < datetime('now', '-30 days')
);

-- 2. Promote hotspots based on incident frequency
UPDATE hotspots SET risk_level = 'critical'
WHERE times_touched >= 10 AND risk_level != 'critical';

UPDATE hotspots SET risk_level = 'high'
WHERE times_touched >= 5 AND times_touched < 10 AND risk_level NOT IN ('critical', 'high');

UPDATE hotspots SET risk_level = 'medium'
WHERE times_touched >= 3 AND times_touched < 5 AND risk_level NOT IN ('critical', 'high', 'medium');

-- 3. Summary stats
SELECT '=== MEMORY HEALTH ===' as report;
SELECT 'Workflow runs' as metric, COUNT(*) as value FROM workflow_runs
UNION ALL SELECT 'Completed', COUNT(*) FROM workflow_runs WHERE status='completed'
UNION ALL SELECT 'Failed', COUNT(*) FROM workflow_runs WHERE status='failed'
UNION ALL SELECT 'Open findings', COUNT(*) FROM findings WHERE status='open'
UNION ALL SELECT 'P0 open', COUNT(*) FROM findings WHERE status='open' AND severity='P0'
UNION ALL SELECT 'P1 open', COUNT(*) FROM findings WHERE status='open' AND severity='P1'
UNION ALL SELECT 'Failed approaches logged', COUNT(*) FROM failed_approaches
UNION ALL SELECT 'Active decisions', COUNT(*) FROM decisions WHERE status='active'
UNION ALL SELECT 'Hotspots tracked', COUNT(*) FROM hotspots
UNION ALL SELECT 'Critical hotspots', COUNT(*) FROM hotspots WHERE risk_level='critical'
UNION ALL SELECT 'Bugs logged', COUNT(*) FROM bugs
UNION ALL SELECT 'Patterns discovered', COUNT(*) FROM patterns;

-- 4. Top 10 hottest files
SELECT file_path, risk_level, times_touched,
    (SELECT COUNT(*) FROM findings f WHERE f.file_path = h.file_path AND f.status='open') as open_findings,
    (SELECT COUNT(*) FROM bugs b WHERE b.affected_files LIKE '%' || h.file_path || '%') as bug_count
FROM hotspots h
ORDER BY times_touched DESC
LIMIT 10;

-- 5. Decay: archive old resolved findings (older than 90 days)
INSERT INTO decay_log (entity_type, entity_id, action, reason)
SELECT 'finding', id, 'archived', 'Resolved more than 90 days ago'
FROM findings
WHERE status IN ('fixed', 'wontfix')
AND created_at < datetime('now', '-90 days')
AND id NOT IN (SELECT entity_id FROM decay_log WHERE entity_type='finding' AND action='archived');

-- 6. Orphaned hotspots — files that no longer exist could be flagged
-- (Agents should run: for each hotspot, check if file exists, if not flag it)
SELECT file_path FROM hotspots
WHERE last_updated < datetime('now', '-60 days');
