-- C1 ownership fix v3: reassign postgres-owned objects in public -> immich.
-- Skips extension members (deptype 'e') and column-linked sequences (deptype 'a'
-- with refobjid = the sequence: those follow their owning table's ALTER).
DO $$
DECLARE
  r record;
  n integer := 0;
BEGIN
  FOR r IN
    SELECT c.oid, c.relkind, c.relname
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND c.relkind IN ('r','p','S','v','m')
       AND pg_get_userbyid(c.relowner) = 'postgres'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = c.oid AND d.deptype = 'e')
  LOOP
    IF r.relkind = 'S' THEN
      IF EXISTS (SELECT 1 FROM pg_depend d
                  WHERE d.objid = r.oid AND d.deptype IN ('a','i')) THEN
        RAISE NOTICE 'skip column-linked sequence %', r.relname;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER SEQUENCE public.%I OWNER TO immich', r.relname);
    ELSE
      EXECUTE format('ALTER TABLE public.%I OWNER TO immich', r.relname);
    END IF;
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'relations reassigned: %', n;

  n := 0;
  FOR r IN
    SELECT t.typname
      FROM pg_type t
     WHERE t.typnamespace = 'public'::regnamespace
       AND t.typtype IN ('e','c')
       AND pg_get_userbyid(t.typowner) = 'postgres'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = t.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER TYPE public.%I OWNER TO immich', r.typname);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'types reassigned: %', n;
END $$;
