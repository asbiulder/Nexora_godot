"""Run with python3 -m unittest supabase.tests.test_cup_cancel_local.

Uses a fresh temporary PostgreSQL cluster, Unix socket only, no external database.
The exact cup_cancel, _cup_refund and relevant grant/revoke statements are taken
from cups.sql; unrelated RPCs are inert stubs. PostgreSQL binaries are required.
"""
import glob
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SQL = (ROOT / 'supabase/cups.sql').read_text(encoding='utf-8')
ENV = {'PATH': '/usr/bin:/bin', 'LC_ALL': 'C', 'HOME': '/tmp'}
OWNER = '00000000-0000-0000-0000-000000000001'
OTHER = '00000000-0000-0000-0000-000000000002'
CUP = '00000000-0000-0000-0000-000000001001'
RUNNING_CUP = '00000000-0000-0000-0000-000000001002'


def extract(pattern):
    match = re.search(pattern, SQL, flags=re.IGNORECASE | re.DOTALL)
    if not match:
        raise AssertionError('required SQL statement not found: ' + pattern)
    return match.group(0)


def pg_bin(name):
    candidates = sorted(glob.glob('/usr/lib/postgresql/*/bin/' + name), reverse=True)
    return candidates[0] if candidates else shutil.which(name)


class CupCancelLocalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.initdb, cls.pg_ctl, cls.psql = (pg_bin(n) for n in ('initdb', 'pg_ctl', 'psql'))
        if not all((cls.initdb, cls.pg_ctl, cls.psql)):
            raise unittest.SkipTest('local PostgreSQL server and client binaries are required')
        cls.temp = tempfile.TemporaryDirectory(prefix='cup-cancel-pg-')
        cls.base = pathlib.Path(cls.temp.name)
        cls.data = cls.base / 'data'
        cls.socket = cls.base / 'socket'
        cls.socket.mkdir()
        cls.started = False
        try:
            subprocess.run([cls.initdb, '-D', str(cls.data), '-A', 'trust', '-U', 'test_owner',
                            '--no-instructions'], check=True, env=ENV, capture_output=True, text=True)
            # listen_addresses='' means no TCP listener. The socket directory is private.
            subprocess.run([cls.pg_ctl, '-D', str(cls.data), '-l', str(cls.base / 'server.log'),
                            '-o', f"-F -k {cls.socket} -p 55432 -c listen_addresses=''",
                            '-w', 'start'], check=True, env=ENV, capture_output=True, text=True)
            cls.started = True
            cls.setup_schema()
        except Exception:
            cls.tearDownClass()
            raise

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, 'started', False):
            subprocess.run([cls.pg_ctl, '-D', str(cls.data), '-m', 'immediate', '-w', 'stop'],
                           check=False, env=ENV, capture_output=True, text=True)
            cls.started = False
        if hasattr(cls, 'temp'):
            cls.temp.cleanup()

    @classmethod
    def command(cls):
        return [cls.psql, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-h', str(cls.socket),
                '-p', '55432', '-U', 'test_owner', '-d', 'postgres']

    @classmethod
    def run_sql(cls, sql):
        return subprocess.run(cls.command(), input=sql, check=True, env=ENV,
                              capture_output=True, text=True).stdout

    @classmethod
    def setup_schema(cls):
        refund = extract(r'create\s+or\s+replace\s+function\s+public\._cup_refund\(.*?\nend\s*\$\$;')
        cancel = extract(r'create\s+or\s+replace\s+function\s+public\.cup_cancel\(.*?\nend\s*\$\$;')
        revoke_helpers = extract(r'revoke\s+execute\s+on\s+function\s+public\._cup_fill\(.*?\sfrom\s+public,\s*anon,\s*authenticated\s*;')
        revoke_cancel = extract(r'revoke\s+execute\s+on\s+function\s+public\.cup_cancel\(.*?\sfrom\s+public,\s*anon,\s*authenticated\s*;')
        grant = extract(r'grant\s+execute\s+on\s+function\s+public\.cup_create\(.*?\sto\s+authenticated\s*;')
        signatures = re.findall(r'public\.(\w+)\(([^)]*)\)', revoke_helpers + grant, flags=re.IGNORECASE)
        stubs = []
        for name, types in signatures:
            if name not in ('_cup_refund', 'cup_cancel'):
                stubs.append(f'create function public.{name}({types}) returns void language plpgsql as $$ begin return; end $$;')
        fixture = """
create role anon;
create role authenticated;
create schema auth;
grant usage on schema auth to anon, authenticated;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create table public.profiles(id uuid primary key, gems int not null);
create table public.cups(id uuid primary key, created_by uuid not null, name text not null,
  status text not null, escrow int not null, cancelled_reason text, finished_at timestamptz);
create table public.cup_players(cup_id uuid, user_id uuid);
create table public.cup_ledger(cup_id uuid, user_id uuid, kind text, place int, gems int,
  unique(cup_id, kind, place));
create table public.notifications(user_id uuid, kind text, title text, body text, data jsonb);
"""
        cls.run_sql('\n'.join([fixture, refund, cancel, *stubs, revoke_helpers, revoke_cancel, grant]))

    def setUp(self):
        self.run_sql(f"""
truncate public.notifications, public.cup_ledger, public.cup_players, public.cups, public.profiles;
insert into public.profiles values ('{OWNER}', 70), ('{OTHER}', 0);
insert into public.cups(id, created_by, name, status, escrow) values
  ('{CUP}', '{OWNER}', 'test', 'registration', 30),
  ('{RUNNING_CUP}', '{OWNER}', 'running', 'running', 0);
""")

    def test_privileges_identity_ownership_and_refund(self):
        self.run_sql(f"""
do $$ begin
  if has_function_privilege('anon', 'public.cup_cancel(uuid)', 'execute') then
    raise exception 'anon must not execute cancellation'; end if;
  if not has_function_privilege('authenticated', 'public.cup_cancel(uuid)', 'execute') then
    raise exception 'authenticated must be able to execute cancellation'; end if;
  if has_function_privilege('authenticated', 'public._cup_refund(uuid,text)', 'execute') then
    raise exception 'refund helper must not be client-executable'; end if;
  if exists (select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
             where p.oid='public.cup_cancel(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE') then
    raise exception 'PUBLIC must not have execute on cancellation'; end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  begin perform public.cup_cancel('{CUP}'); raise exception 'null uid unexpectedly succeeded';
  exception when raise_exception then if sqlerrm <> 'not signed in' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub', '{OTHER}', false);
do $$ begin
  begin perform public.cup_cancel('{CUP}'); raise exception 'non-owner unexpectedly succeeded';
  exception when raise_exception then if sqlerrm <> 'organizer only' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub', '{OWNER}', false);
do $$ begin
  begin perform public.cup_cancel('{RUNNING_CUP}'); raise exception 'running cup unexpectedly cancelled';
  exception when raise_exception then if sqlerrm <> 'already started' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if (select status from public.cups where id='{CUP}') <> 'registration'
     or (select escrow from public.cups where id='{CUP}') <> 30
     or (select gems from public.profiles where id='{OWNER}') <> 70
     or exists (select 1 from public.cup_ledger) then
    raise exception 'rejected attempts changed state'; end if;
end $$;
set role authenticated;
select public.cup_cancel('{CUP}');
do $$ begin
  begin perform public.cup_cancel('{CUP}'); raise exception 'repeat unexpectedly succeeded';
  exception when raise_exception then if sqlerrm <> 'already started' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if (select status from public.cups where id='{CUP}') <> 'cancelled'
     or (select escrow from public.cups where id='{CUP}') <> 0
     or (select gems from public.profiles where id='{OWNER}') <> 100
     or (select count(*) from public.cup_ledger where cup_id='{CUP}' and kind='refund' and gems=30) <> 1 then
    raise exception 'owner refund did not occur exactly once'; end if;
end $$;
""")

    def test_cancel_waits_for_concurrent_running_transition(self):
        # The update remains uncommitted while cancel begins: cancel must lock
        # before checking registration, then observe the committed running state.
        locker_sql = f"""begin;
update public.cups set status='running' where id='{CUP}';
select pg_advisory_xact_lock(843742);
select pg_sleep(2);
commit;"""
        process = subprocess.Popen(self.command(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, env=ENV, text=True)
        process.stdin.write(locker_sql)
        process.stdin.close()
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                locks = self.run_sql("select count(*) from pg_locks where locktype='advisory' and objid=843742 and granted;")
                if re.search(r'\b1\b', locks):
                    break
                time.sleep(0.05)
            else:
                self.fail('concurrent updater did not acquire its lock')
            self.run_sql(f"""
set role authenticated;
select set_config('request.jwt.claim.sub', '{OWNER}', false);
do $$ begin
  begin perform public.cup_cancel('{CUP}'); raise exception 'concurrent running cup cancelled';
  exception when raise_exception then if sqlerrm <> 'already started' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if (select status from public.cups where id='{CUP}') <> 'running'
     or (select escrow from public.cups where id='{CUP}') <> 30
     or exists (select 1 from public.cup_ledger) then
    raise exception 'concurrent state or escrow changed'; end if;
end $$;
""")
            self.assertEqual(process.wait(timeout=5), 0, process.stderr.read())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()
            process.stderr.close()


if __name__ == '__main__':
    unittest.main()
