-- NEXORA tournament upgrades: custom series, organizer approval, manual real-prize tracking,
-- 10-minute check-in/reminder, 30-second lineup, and shared host-selected field/ball.
-- Additive and rerunnable. Cash prizes are metadata and manual settlement only; this migration does not move money.

create or replace function public.cup_cfg() returns jsonb language sql immutable as $$
  select '{"lineup_s":30,"gap_s":12,"checkin_min":10,"replace_min":5,"noshow_min":5,"remind_min":10,
           "game_min":6,"buffer_min":4,"max_players":64,"max_prize":100,"max_games":9,"presence_s":45}'::jsonb $$;

alter table public.cups
  add column if not exists require_approval boolean not null default false,
  add column if not exists series_mode text not null default 'legacy',
  add column if not exists target_wins int not null default 2,
  add column if not exists prize_title text not null default '',
  add column if not exists cash_prize numeric(12,2) not null default 0,
  add column if not exists cash_currency text;

do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_series_mode_check') then
    alter table public.cups add constraint cups_series_mode_check check (series_mode in ('legacy','single','aggregate','first_to'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_target_wins_check') then
    alter table public.cups add constraint cups_target_wins_check check (target_wins between 1 and 5);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.cups'::regclass and conname = 'cups_cash_prize_check') then
    alter table public.cups add constraint cups_cash_prize_check check (cash_prize >= 0);
  end if;
end $$;

alter table public.cup_players drop constraint if exists cup_players_status_check;
alter table public.cup_players add constraint cup_players_status_check check (status in ('pending','main','wait','out'));

create table if not exists public.cup_payouts (
  cup_id uuid not null references public.cups(id) on delete cascade,
  place int not null check (place between 1 and 3),
  user_id uuid not null references public.profiles(id) on delete restrict,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null,
  status text not null default 'pending' check (status in ('pending','paid')),
  paid_by uuid references public.profiles(id),
  paid_at timestamptz,
  receipt_note text,
  primary key (cup_id, place)
);
alter table public.cup_payouts enable row level security;
drop policy if exists "cup_payouts read" on public.cup_payouts;
create policy "cup_payouts read" on public.cup_payouts for select using (
  exists (select 1 from public.cups c where c.id=cup_payouts.cup_id and c.created_by=auth.uid())
  or exists (select 1 from public.cup_players p where p.cup_id=cup_payouts.cup_id and p.user_id=auth.uid())
);
grant select on public.cup_payouts to authenticated;
revoke select on public.cup_payouts from anon;
revoke insert, update, delete on public.cup_payouts from anon, authenticated;
do $$ begin
  begin alter publication supabase_realtime add table public.cup_payouts; exception when others then null; end;
end $$;

create or replace function public._cup_cash_shares(p numeric, sp int[]) returns numeric[] language plpgsql immutable as $$
declare a numeric[] := array[round(p*sp[1]/100.0,2), round(p*sp[2]/100.0,2), round(p*sp[3]/100.0,2)]; begin
  a[1] := round(a[1] + p - a[1] - a[2] - a[3], 2);
  return a;
end $$;

create or replace function public.cup_create_v2(
  p_name text, p_max int, p_games int, p_goals int, p_starts timestamptz,
  p_prize int, p_split int[], p_join boolean, p_require_approval boolean,
  p_series_mode text, p_target_wins int, p_prize_title text,
  p_cash_prize numeric, p_cash_currency text
) returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; cd text; sp int[] := coalesce(p_split, '{60,30,10}'); mode text := coalesce(p_series_mode,'');
        wins int := coalesce(p_target_wins,0); cash numeric := round(coalesce(p_cash_prize,0),2); curr text := upper(trim(coalesce(p_cash_currency,'')));
begin
  if uid is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_name,''))) < 3 or char_length(trim(coalesce(p_name,''))) > 40 then raise exception 'title required'; end if;
  if p_max is null or p_max < 2 or p_max > public._cupc('max_players') then raise exception 'bad size'; end if;
  if p_goals is null or p_goals < 1 or p_goals > 10 then raise exception 'bad format'; end if;
  if p_starts is null or p_starts < now() + interval '2 minutes' or p_starts > now() + interval '60 days' then raise exception 'bad start time'; end if;
  if p_prize is null or p_prize < 0 or p_prize > public._cupc('max_prize') then raise exception 'bad prize'; end if;
  if coalesce(array_length(sp,1),0) <> 3 or sp[1] < sp[2] or sp[2] < sp[3] or sp[3] < 0 or sp[1]+sp[2]+sp[3] <> 100 then raise exception 'bad split'; end if;
  if p_games is null or p_target_wins is null then raise exception 'bad series'; end if;
  if mode = 'single' and (p_games <> 1 or wins <> 1) then raise exception 'bad series'; end if;
  if mode = 'aggregate' and (p_games < 2 or p_games > public._cupc('max_games') or wins <> 1) then raise exception 'bad series'; end if;
  if mode = 'first_to' and (wins < 1 or wins > 5 or p_games <> (2*wins-1) or p_games > public._cupc('max_games')) then raise exception 'bad series'; end if;
  if mode not in ('single','aggregate','first_to') then raise exception 'bad series'; end if;
  if cash < 0 or cash > 9999999999.99 then raise exception 'bad cash prize'; end if;
  if (cash > 0 and curr = '') or char_length(curr) > 12 then raise exception 'cash currency required'; end if;
  if char_length(coalesce(p_prize_title,'')) > 120 then raise exception 'prize title too long'; end if;
  if (select count(*) from cups where created_by = uid and status in ('registration','running')) >= 3 then raise exception 'too many open tournaments'; end if;
  if p_prize > 0 then
    update profiles set gems = gems - p_prize where id = uid and gems >= p_prize;
    if not found then raise exception 'not enough gems'; end if;
  end if;
  loop
    cd := (10000 + floor(random()*90000))::int::text;
    exit when not exists (select 1 from cups where code = cd);
  end loop;
  insert into cups(code,name,created_by,max_players,games,goals,starts_at,prize,split,escrow,
                   require_approval,series_mode,target_wins,prize_title,cash_prize,cash_currency)
    values(cd,trim(p_name),uid,p_max,p_games,p_goals,date_trunc('minute',p_starts),p_prize,sp,p_prize,
           coalesce(p_require_approval,false),mode,wins,left(trim(coalesce(p_prize_title,'')),120),cash,nullif(curr,'')) returning * into c;
  if p_prize > 0 then insert into cup_ledger(cup_id,user_id,kind,place,gems) values(c.id,uid,'escrow',0,-p_prize); end if;
  if coalesce(p_join,true) then insert into cup_players(cup_id,user_id,status) values(c.id,uid,'main'); end if;
  return c;
end $$;

create or replace function public.cup_join(p_code text) returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; st text; n int; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where code = trim(p_code) for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if exists (select 1 from cup_players where cup_id=c.id and user_id=uid and status in ('pending','main','wait')) then return c; end if;
  if c.status <> 'registration' or now() >= c.starts_at then raise exception 'registration closed'; end if;
  select count(*) into n from cup_players where cup_id=c.id and status='main';
  st := case when c.require_approval then 'pending' when n < c.max_players then 'main' else 'wait' end;
  insert into cup_players(cup_id,user_id,status) values(c.id,uid,st)
    on conflict(cup_id,user_id) do update set status=excluded.status, joined_at=clock_timestamp(), checked_in_at=null, note=null;
  if st='pending' then
    perform public._notify(c.created_by,'cup_join_request','درخواست عضویت در «'||c.name||'»','یک بازیکن منتظر تأیید توست',jsonb_build_object('cup',c.id,'user',uid));
  end if;
  return c;
end $$;

create or replace function public.cup_approve(p_cup uuid, p_user uuid, p_approve boolean) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; n int; next_status text; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where id=p_cup for update;
  if c.id is null or c.status <> 'registration' then raise exception 'registration closed'; end if;
  if c.created_by is distinct from uid then raise exception 'organizer only'; end if;
  if not exists(select 1 from cup_players where cup_id=p_cup and user_id=p_user and status='pending') then raise exception 'approval request not found'; end if;
  if p_approve then
    select count(*) into n from cup_players where cup_id=p_cup and status='main';
    next_status := case when n < c.max_players then 'main' else 'wait' end;
    update cup_players set status=next_status,note=null where cup_id=p_cup and user_id=p_user;
    perform public._notify(p_user,'cup_approved','درخواستت برای «'||c.name||'» تأیید شد',case when next_status='wait' then 'در صف انتظار هستی' else 'برای اعلام حضور آماده باش' end,jsonb_build_object('cup',c.id));
  else
    update cup_players set status='out',note='rejected' where cup_id=p_cup and user_id=p_user;
    perform public._notify(p_user,'cup_rejected','درخواست عضویت در «'||c.name||'» پذیرفته نشد',null,jsonb_build_object('cup',c.id));
  end if;
end $$;

create or replace function public._cup_series_winner_v2(mode text,n int,target int,w1 int,w2 int,g1 int,g2 int,played int)
returns int language plpgsql immutable as $$
begin
  if mode is null or mode='legacy' then return public._cup_series_winner(n,w1,w2,g1,g2,played); end if;
  if mode='single' then
    if played < 1 then return 0; end if;
    return case when g1 >= g2 then 1 else 2 end;
  elsif mode='first_to' then
    if w1 >= target then return 1; end if;
    if w2 >= target then return 2; end if;
    if played >= n then
      if w1 <> w2 then return case when w1 > w2 then 1 else 2 end; end if;
      if g1 <> g2 then return case when g1 > g2 then 1 else 2 end; end if;
      if played >= n+3 then return 1; end if;
    end if;
    return 0;
  elsif mode='aggregate' then
    if played < n then return 0; end if;
    if g1 <> g2 then return case when g1 > g2 then 1 else 2 end; end if;
    if played >= n+3 then return 1; end if;
    return 0;
  end if;
  raise exception 'bad series mode';
end $$;

create or replace function public._cup_on_match() returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid; m cup_matches; c cups; flip boolean; g1 int; g2 int; w int; begin
  if new.status = old.status or new.status = 'live' then return new; end if;
  select cup_match_id into mid from rooms where id = new.room_id;
  if mid is null then return new; end if;
  if new.bots then return new; end if;
  if new.status = 'abandoned' then
    update cup_matches set wait_from=now(),lineup_until=null where id=mid and status in ('ready','live');
    return new;
  end if;
  select * into m from cup_matches where id=mid for update;
  if m.status not in ('ready','live') then return new; end if;
  flip := coalesce(new.team_a[1]=m.p2,false);
  g1 := coalesce(case when flip then new.score_b else new.score_a end,0);
  g2 := coalesce(case when flip then new.score_a else new.score_b end,0);
  insert into cup_games(match_id,game_no,match_ref,g1,g2,winner)
    values(mid,m.games_played+1,new.id,g1,g2,case when g1>g2 then m.p1 when g2>g1 then m.p2 end) on conflict do nothing;
  if not found then return new; end if;
  update cup_matches set games_played=games_played+1,wins1=wins1+(g1>g2)::int,wins2=wins2+(g2>g1)::int,
    goals1=goals1+g1,goals2=goals2+g2,wait_from=now(),lineup_until=now()+make_interval(secs=>public._cupc('gap_s')+public._cupc('lineup_s'))
    where id=mid returning * into m;
  select * into c from cups where id=m.cup_id;
  w := public._cup_series_winner_v2(c.series_mode,c.games,c.target_wins,m.wins1,m.wins2,m.goals1,m.goals2,m.games_played);
  if w=1 then perform public._cup_advance(mid,m.p1,m.p2,false);
  elsif w=2 then perform public._cup_advance(mid,m.p2,m.p1,false); end if;
  return new;
end $$;

create or replace function public._cup_make_cash_payouts() returns trigger language plpgsql security definer set search_path = public as $$
declare shares numeric[]; u uuid; pl int; amount numeric; begin
  if new.status <> 'finished' or old.status='finished' or new.cash_prize <= 0 or new.cash_currency is null then return new; end if;
  shares := public._cup_cash_shares(new.cash_prize,new.split);
  -- If a podium place does not exist, its share is added to first place so the advertised total is fully allocated.
  if not exists(select 1 from cup_players where cup_id=new.id and final_place=2) then shares[1] := shares[1]+shares[2]; shares[2] := 0; end if;
  if not exists(select 1 from cup_players where cup_id=new.id and final_place=3) then shares[1] := shares[1]+shares[3]; shares[3] := 0; end if;
  for pl in 1..3 loop
    continue when shares[pl] <= 0;
    select user_id into u from cup_players where cup_id=new.id and final_place=pl limit 1;
    if u is not null then
      insert into cup_payouts(cup_id,place,user_id,amount,currency) values(new.id,pl,u,shares[pl],new.cash_currency) on conflict(cup_id,place) do nothing;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_cup_cash_payouts on public.cups;
create trigger trg_cup_cash_payouts after update of status on public.cups for each row execute function public._cup_make_cash_payouts();

create or replace function public.cup_mark_payout_paid(p_cup uuid,p_place int,p_note text default null) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where id=p_cup;
  if c.id is null or c.status <> 'finished' then raise exception 'tournament not finished'; end if;
  if c.created_by is distinct from uid then raise exception 'organizer only'; end if;
  update cup_payouts set status='paid',paid_by=uid,paid_at=coalesce(paid_at,now()),receipt_note=left(trim(coalesce(p_note,'')),240)
    where cup_id=p_cup and place=p_place and status='pending';
  if not found and not exists(select 1 from cup_payouts where cup_id=p_cup and place=p_place and status='paid') then raise exception 'payout not found'; end if;
end $$;

create or replace function public.cup_set_room_assets(p_match uuid,p_field int,p_ball int) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m cup_matches; r rooms; begin
  if uid is null then raise exception 'not signed in'; end if;
  if p_field is null or p_ball is null or p_field < 0 or p_field > 39 or p_ball < 0 or p_ball > 35 then raise exception 'bad room assets'; end if;
  select * into m from cup_matches where id=p_match for update;
  if m.id is null or m.status not in ('ready','live') or m.room_id is null then raise exception 'match not ready'; end if;
  select * into r from rooms where id=m.room_id for update;
  if r.host is distinct from uid or r.status <> 'waiting' then raise exception 'room host only'; end if;
  if m.lineup_until is not null and now() >= m.lineup_until then raise exception 'lineup closed'; end if;
  update rooms set settings=coalesce(settings,'{}'::jsonb)||jsonb_build_object('field',p_field,'ball',p_ball,'shared_assets',true) where id=r.id;
end $$;

create or replace function public._cup_close_pending_on_draw() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status='registration' and new.status='running' then
    update cup_players set status='out',note='approval expired' where cup_id=new.id and status='pending';
  end if;
  return new;
end $$;
drop trigger if exists trg_cup_close_pending_on_draw on public.cups;
create trigger trg_cup_close_pending_on_draw before update of status on public.cups for each row execute function public._cup_close_pending_on_draw();

revoke execute on function public._cup_cash_shares(numeric,int[]), public._cup_series_winner_v2(text,int,int,int,int,int,int,int),
  public._cup_make_cash_payouts(), public._cup_close_pending_on_draw() from public,anon,authenticated;
revoke execute on function public.cup_create_v2(text,int,int,int,timestamptz,int,int[],boolean,boolean,text,int,text,numeric,text),
  public.cup_approve(uuid,uuid,boolean), public.cup_mark_payout_paid(uuid,int,text), public.cup_set_room_assets(uuid,int,int) from public,anon;
grant execute on function public.cup_create_v2(text,int,int,int,timestamptz,int,int[],boolean,boolean,text,int,text,numeric,text),
  public.cup_approve(uuid,uuid,boolean), public.cup_mark_payout_paid(uuid,int,text), public.cup_set_room_assets(uuid,int,int) to authenticated;
grant execute on function public.cup_join(text) to authenticated;

notify pgrst, 'reload schema';
