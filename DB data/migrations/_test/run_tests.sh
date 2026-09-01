#!/usr/bin/env bash
# Apply the hand-run Supabase migrations to a throwaway local PostgreSQL and assert their behaviour.
#
# These migrations cannot be tested against the live Supabase database -- they are applied by hand,
# once, and there is no staging copy. So instead the schema is reconstructed locally from
# DB data/schema.sql + Enum.json (see baseline.sql) and the migrations run against that.
#
# Each migration file is applied with psql -1, i.e. as ONE transaction, which is how the Supabase
# SQL editor runs a pasted file. If a file only works when split, it fails here.
#
# Usage:  ./run_tests.sh          (needs postgresql-16 installed; run as root, it drops to the
#                                  postgres system user because initdb refuses to run as root)
set -euo pipefail

PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=${WORK:-/tmp/korra-pgtest}
PORT=${PORT:-5599}

rm -rf "$WORK"; mkdir -p "$WORK"; chmod 777 "$WORK"
chown -R postgres:postgres "$WORK"

su postgres -c "$PGBIN/initdb -U postgres -A trust $WORK/data" >/dev/null
su postgres -c "$PGBIN/pg_ctl -D $WORK/data -o \"-k $WORK -p $PORT -c listen_addresses=''\" -l $WORK/log start" >/dev/null
trap 'su postgres -c "$PGBIN/pg_ctl -D $WORK/data -m immediate stop" >/dev/null 2>&1 || true' EXIT
sleep 2

cp "$HERE/baseline.sql" "$HERE/tests.sql" "$WORK/"
cp "$HERE/../0002_project_items_line_grain.sql"            "$WORK/m2.sql"
cp "$HERE/../0003_project_notes_review_notifications.sql"  "$WORK/m3.sql"
cp "$HERE/../0004_tender_stage_and_commercial_fields.sql"  "$WORK/m4.sql"
cp "$HERE/../0005_analytics_views.sql"                     "$WORK/m5.sql"
chmod -R a+r "$WORK"

su postgres -c "$PGBIN/createdb -h $WORK -p $PORT -U postgres korra"
for f in baseline m2 m3 m4 m5; do
  printf '%-10s ' "$f"
  su postgres -c "$PGBIN/psql -h $WORK -p $PORT -U postgres -d korra -1 -v ON_ERROR_STOP=1 -q -f $WORK/$f.sql"
  echo "applied"
done

su postgres -c "$PGBIN/psql -h $WORK -p $PORT -U postgres -d korra -v ON_ERROR_STOP=1 -q -f $WORK/tests.sql" \
  > "$WORK/out.txt" 2>&1 || { echo "TESTS FAILED:"; grep -A2 ERROR "$WORK/out.txt" | head -10; exit 1; }

grep "NOTICE:  pass" "$WORK/out.txt" | sed 's/.*NOTICE:  pass  /  ok  /'
echo "ALL PASSED ($(grep -c 'NOTICE:  pass' "$WORK/out.txt") assertions)"
