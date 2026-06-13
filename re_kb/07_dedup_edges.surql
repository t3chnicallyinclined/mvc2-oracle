-- ============================================================================
-- 07: dedup edge tables. RELATE is NOT idempotent; re-running seeds duplicates.
-- Graph arrows (->reads->) require edges created by RELATE (it maintains the
-- bidirectional graph refs); a plain CREATE on an edge table does NOT. So we
-- snapshot DISTINCT (in,out) pairs per table, wipe, then RELATE each pair back.
-- The arrow position needs a LITERAL table name, hence one block per table.
-- Run AFTER (re-)applying the seed files. Safe to run repeatedly.
-- ============================================================================
USE NS re DB kb;

LET $reads = (SELECT in, out FROM reads GROUP BY in, out);
DELETE reads;
FOR $p IN $reads { RELATE ($p.in)->reads->($p.out); };

LET $writes = (SELECT in, out FROM writes GROUP BY in, out);
DELETE writes;
FOR $p IN $writes { RELATE ($p.in)->writes->($p.out); };

LET $calls = (SELECT in, out FROM calls GROUP BY in, out);
DELETE calls;
FOR $p IN $calls { RELATE ($p.in)->calls->($p.out); };

LET $lives_at = (SELECT in, out FROM lives_at GROUP BY in, out);
DELETE lives_at;
FOR $p IN $lives_at { RELATE ($p.in)->lives_at->($p.out); };

LET $maps_to = (SELECT in, out FROM maps_to GROUP BY in, out);
DELETE maps_to;
FOR $p IN $maps_to { RELATE ($p.in)->maps_to->($p.out); };

LET $about = (SELECT in, out FROM about GROUP BY in, out);
DELETE about;
FOR $p IN $about { RELATE ($p.in)->about->($p.out); };

LET $cites = (SELECT in, out FROM cites GROUP BY in, out);
DELETE cites;
FOR $p IN $cites { RELATE ($p.in)->cites->($p.out); };

LET $has_field = (SELECT in, out FROM has_field GROUP BY in, out);
DELETE has_field;
FOR $p IN $has_field { RELATE ($p.in)->has_field->($p.out); };

LET $instance_of = (SELECT in, out FROM instance_of GROUP BY in, out);
DELETE instance_of;
FOR $p IN $instance_of { RELATE ($p.in)->instance_of->($p.out); };

LET $owns = (SELECT in, out FROM owns GROUP BY in, out);
DELETE owns;
FOR $p IN $owns { RELATE ($p.in)->owns->($p.out); };

LET $part_of = (SELECT in, out FROM part_of GROUP BY in, out);
DELETE part_of;
FOR $p IN $part_of { RELATE ($p.in)->part_of->($p.out); };

LET $confirms = (SELECT in, out FROM confirms GROUP BY in, out);
DELETE confirms;
FOR $p IN $confirms { RELATE ($p.in)->confirms->($p.out); };
