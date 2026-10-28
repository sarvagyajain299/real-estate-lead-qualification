-- Lead Qualification System — v1.0.0 — 2026-08-28
-- Full schema and seed for the `lqs` schema.
-- Target: Supabase project "UAE off plan lead qualifier V1" (ludgsvcqqsrxshiahekx)
--
-- Run top to bottom on an empty database. It is safe to run against a project that
-- already has an unrelated `public` schema; nothing here touches `public`.
--
-- To undo everything this file creates:  drop schema lqs cascade;

-- ---------------------------------------------------------------------------
-- 1. Schema and tables (spec section 3)
-- ---------------------------------------------------------------------------

create schema if not exists lqs;

create table lqs.markets (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  currency text not null,
  timezone text not null,
  default_language text not null default 'en',
  working_hours jsonb not null,
  min_notice_hours int not null default 3,
  booking_window_days int not null default 7,
  buffer_seconds jsonb not null default '{"telegram":5,"whatsapp":5,"webchat":5,"email":60}',
  thresholds jsonb not null,
  disclaimers jsonb default '{}',
  fx_rates jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table lqs.agents (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references lqs.markets(id),
  full_name text not null,
  telegram_chat_id text,
  email text,
  calendar_id text not null,
  timezone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table lqs.leads (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references lqs.markets(id),
  full_name text,
  phone text,
  email text,
  primary_language text,
  timezone text,
  source text,
  status text not null default 'new',
  assigned_agent_id uuid references lqs.agents(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on lqs.leads (status);

create table lqs.lead_identities (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references lqs.leads(id) on delete cascade,
  channel text not null,
  external_id text not null,
  display_name text,
  created_at timestamptz not null default now(),
  unique (channel, external_id)
);

create table lqs.conversations (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references lqs.leads(id),
  market_id uuid not null references lqs.markets(id),
  deal_type text not null default 'offplan',
  channel text not null,
  language text,
  status text not null default 'active',
  bot_muted boolean not null default false,
  escalation_reason text,
  processing_until timestamptz,
  questions_asked int not null default 0,
  unparsed_streak int not null default 0,
  repeat_streak int not null default 0,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on lqs.conversations (status, last_inbound_at);

create table lqs.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references lqs.conversations(id),
  direction text not null,
  channel text not null,
  external_message_id text,
  body text,
  raw jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

-- The single most important constraint in this schema. Telegram retries webhooks and
-- n8n retries failed executions; without this, one retry produces a duplicate reply.
-- Note: external_message_id is normalised as "<chat_id>:<message_id>", not the bare
-- Telegram message_id, because Telegram message ids are unique per chat rather than
-- globally. See docs/PROMPT.md, Clarifications.
create unique index messages_external_uniq
  on lqs.messages (channel, external_message_id)
  where external_message_id is not null;
create index on lqs.messages (conversation_id, created_at desc);

create table lqs.slot_definitions (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references lqs.markets(id),
  deal_type text not null,
  slot_key text not null,
  tier int not null,
  priority int not null,
  required boolean not null default false,
  value_type text not null,
  question_open text not null,
  question_choices jsonb,
  condition jsonb,
  extraction_hint text,
  active boolean not null default true,
  unique (market_id, deal_type, slot_key)
);

create table lqs.qualification (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references lqs.conversations(id),
  slot_key text not null,
  value jsonb,
  state text not null default 'empty',
  attempts int not null default 0,
  previous_values jsonb not null default '[]',
  updated_at timestamptz not null default now(),
  unique (conversation_id, slot_key)
);

create table lqs.projects (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references lqs.markets(id),
  name text not null,
  developer text not null,
  area text not null,
  sub_area text,
  latitude numeric,
  longitude numeric,
  handover_quarter text,
  handover_date date,
  payment_plan jsonb,
  resale_threshold_pct int,
  gross_yield_estimate numeric,
  status text not null default 'available',
  description text,
  brochure_url text,
  active boolean not null default true
);

create table lqs.unit_types (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references lqs.projects(id) on delete cascade,
  bedrooms int not null,
  bathrooms int,
  size_sqft_min int,
  size_sqft_max int,
  price_from numeric not null,
  price_to numeric,
  service_charge_per_sqft numeric,
  available_units int
);
create index on lqs.unit_types (bedrooms, price_from);

create table lqs.bookings (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references lqs.conversations(id),
  lead_id uuid not null references lqs.leads(id),
  agent_id uuid not null references lqs.agents(id),
  starts_at timestamptz,
  ends_at timestamptz,
  calendar_event_id text,
  status text not null,
  offered_slots jsonb,
  created_at timestamptz not null default now()
);

create table lqs.briefs (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references lqs.conversations(id),
  booking_id uuid references lqs.bookings(id),
  content_markdown text not null,
  content_blocks jsonb not null,
  delivered_to jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. Market, agent and the thirteen questions (spec sections 4.1, 4.2, 4.4)
--
-- agents.calendar_id must be a real calendar address, never the literal 'primary'.
-- n8n's Google Calendar resource locator validates the id format and rejects 'primary',
-- even though the Google API itself accepts it.
-- ---------------------------------------------------------------------------

insert into lqs.markets (code, name, currency, timezone, default_language, working_hours, min_notice_hours, booking_window_days, thresholds)
values (
  'AE','United Arab Emirates','AED','Asia/Dubai','en',
  '{"sun":["09:00","19:00"],"mon":["09:00","19:00"],"tue":["09:00","19:00"],"wed":["09:00","19:00"],"thu":["09:00","19:00"],"fri":null,"sat":["10:00","16:00"]}'::jsonb,
  3, 7,
  '{"escalate_high_value_min_budget":5000000,"escalate_high_value_payment_methods":["cash"],"escalate_unparsed_streak":2,"escalate_repeat_streak":2,"nurture_max_budget":500000,"nurture_max_timeline_months":12,"nurture_purposes":["browsing"],"max_questions":8,"slot_max_attempts":2,"lock_seconds":60}'::jsonb
);

-- Exchange rates into the market currency. A lead may quote any currency; the value is
-- normalised in LQS - Qualification: save answers before any threshold or listing search
-- sees the number. AED is pegged to USD at 3.6725, so that rate is exact and permanent.
-- The rest are approximate and should be reviewed periodically.
update lqs.markets set fx_rates = '{
  "AED": 1, "USD": 3.6725, "EUR": 3.95, "GBP": 4.65,
  "SAR": 0.979, "QAR": 1.009, "KWD": 11.95, "BHD": 9.74, "OMR": 9.54,
  "INR": 0.0441, "PKR": 0.0132, "CAD": 2.65, "AUD": 2.40,
  "CHF": 4.15, "CNY": 0.505, "RUB": 0.039
}'::jsonb where code = 'AE';

-- Every fixed sentence the bot sends, keyed by line name then BCP-47 language.
-- A new market ships its own wording as data. English is the fallback.
-- Note: a human cannot take over a Telegram chat, so no line may promise a message in
-- this thread. After a booking the next contact is the call itself.
update lqs.markets set disclaimers = '{
  "handover_line": {
    "en": "Thanks - I have passed this to our agent along with everything you have told me. They will follow up with you directly on the number you gave me.",
    "ar": "شكرًا لك - لقد حوّلت طلبك إلى المستشار مع كل التفاصيل التي ذكرتها، وسيتواصل معك مباشرة على الرقم الذي زوّدتني به."
  },
  "nurture_line": {
    "en": "Thanks for going through that with me. Nothing on our books is the right fit right now, but I will keep you posted as new launches come in.",
    "ar": "شكرًا على وقتك. لا يوجد لدينا حاليًا ما يناسب طلبك، لكنني سأبقيك على اطلاع بأي مشاريع جديدة."
  },
  "no_slots_line": {
    "en": "Thanks - there is nothing free in the next few days, so our agent will contact you directly on the number you gave me to fix a time.",
    "ar": "شكرًا لك - لا تتوفر مواعيد خلال الأيام القادمة، لذا سيتواصل معك المستشار مباشرة على رقمك لتحديد موعد."
  },
  "offer_line": {
    "en": "Here are the next few times the agent is free:",
    "ar": "هذه أقرب المواعيد المتاحة لدى المستشار:"
  },
  "offer_prompt_line": {
    "en": "Just tell me which one suits you.",
    "ar": "أخبرني أي موعد يناسبك."
  },
  "booked_line": {
    "en": "Done - you are booked in for {slot}. The agent has everything you have told me and will speak to you then. Nothing else needed from you.",
    "ar": "تم - موعدك محجوز {slot}. لدى المستشار كل التفاصيل التي ذكرتها وسيتحدث معك حينها. لا حاجة لأي إجراء آخر منك."
  },
  "slot_taken_line": {
    "en": "That time has just been taken. Which of the other times works for you?",
    "ar": "هذا الموعد لم يعد متاحًا. أي من المواعيد الأخرى يناسبك؟"
  },
  "already_booked_line": {
    "en": "You are all set for {slot}. See you on the call.",
    "ar": "كل شيء جاهز لموعدك {slot}. أراك في المكالمة."
  }
}'::jsonb where code = 'AE';

insert into lqs.agents (market_id, full_name, telegram_chat_id, email, calendar_id, timezone, active)
select id, 'Example Agent', 'TELEGRAM_CHAT_ID', 'YOUR_EMAIL@example.com', 'YOUR_EMAIL@example.com', 'Asia/Dubai', true
from lqs.markets where code='AE';

insert into lqs.slot_definitions (market_id, deal_type, slot_key, tier, priority, required, value_type, question_open, question_choices, condition, extraction_hint, active)
select m.id, 'offplan', s.slot_key, s.tier, s.priority, s.required, s.value_type, s.question_open, s.question_choices, s.condition, s.extraction_hint, true
from lqs.markets m,
(values
 ('purpose',1,10,true,'enum',
  'Are you looking at this as an investment, or somewhere you''d live in yourself?',
  '[{"label":"Investment","value":"investment"},{"label":"To live in","value":"end_use"},{"label":"Both","value":"both"},{"label":"Just browsing for now","value":"browsing"}]'::jsonb,
  null::jsonb,
  'Classify why they are buying. "rental income", "yield", "ROI" imply investment. "for my family", "move in" imply end_use.'),
 ('budget',1,20,true,'currency_range',
  'Roughly what budget are you working with? A range is fine.',
  '[{"label":"Under 1.5M AED","value":{"min":0,"max":1500000}},{"label":"1.5M - 3M AED","value":{"min":1500000,"max":3000000}},{"label":"3M - 6M AED","value":{"min":3000000,"max":6000000}},{"label":"6M+ AED","value":{"min":6000000,"max":null}}]'::jsonb,
  null::jsonb,
  'Return {min, max, currency}. "around 3 million" means {min: 2700000, max: 3300000}. "up to 2M" means {min: 0, max: 2000000}. Assume AED unless another currency is named.'),
 ('payment_method',1,30,true,'enum',
  'Will you be paying cash, or looking at a mortgage or a developer payment plan?',
  '[{"label":"Cash","value":"cash"},{"label":"Mortgage","value":"mortgage"},{"label":"Developer payment plan","value":"developer_plan"},{"label":"Not sure yet","value":"unsure"}]'::jsonb,
  null::jsonb,
  'Classify how they intend to pay. "loan", "finance", "bank" imply mortgage. "instalments", "plan" imply developer_plan.'),
 ('timeline',1,40,true,'enum',
  'When are you looking to buy?',
  '[{"label":"Within 3 months","value":"0_3m"},{"label":"3-6 months","value":"3_6m"},{"label":"6-12 months","value":"6_12m"},{"label":"Just exploring","value":"exploring"}]'::jsonb,
  null::jsonb,
  'Map to the nearest bucket. "next year" is 6_12m. "ASAP" is 0_3m.'),
 ('contact',1,45,true,'contact',
  'What''s the best name and number to reach you on?',
  null::jsonb,
  null::jsonb,
  'Extract {full_name, phone, email}. At least one of phone or email must be present to count as filled. Keep the phone in the format the lead wrote it, including country code if given.'),
 ('unit_type',2,50,false,'enum',
  'What size are you after?',
  '[{"label":"Studio","value":"0"},{"label":"1 bed","value":"1"},{"label":"2 bed","value":"2"},{"label":"3 bed","value":"3"},{"label":"4+ bed","value":"4"},{"label":"Open to options","value":"any"}]'::jsonb,
  null::jsonb,
  'Bedroom count as a string. "studio" is "0". "two bedroom", "2BR", "2 bed" are "2". Four or more bedrooms is "4".'),
 ('area_preference',2,60,false,'enum',
  'Any particular areas in mind, or are you open to suggestions?',
  '[{"label":"Downtown","value":"downtown"},{"label":"Marina & JBR","value":"marina"},{"label":"Business Bay","value":"business_bay"},{"label":"Dubai Hills","value":"dubai_hills"},{"label":"Creek Harbour","value":"creek_harbour"},{"label":"Open to suggestions","value":"any"}]'::jsonb,
  null::jsonb,
  'Map named Dubai areas to the nearest choice. "JBR" and "Dubai Marina" are marina. "Burj Khalifa area" is downtown.'),
 ('residency',2,70,false,'enum',
  'Are you based in the UAE, or buying from overseas?',
  '[{"label":"UAE resident","value":"uae"},{"label":"Elsewhere in the GCC","value":"gcc"},{"label":"Overseas","value":"overseas"}]'::jsonb,
  null::jsonb,
  'Where the lead currently lives. Saudi, Qatar, Kuwait, Bahrain, Oman are gcc. Anywhere outside the GCC is overseas.'),
 ('handover_preference',2,80,false,'enum',
  'Do you want something handing over soon, or is a later handover fine?',
  '[{"label":"2026","value":"2026"},{"label":"2027","value":"2027"},{"label":"2028 or later","value":"2028_plus"},{"label":"Flexible","value":"any"}]'::jsonb,
  null::jsonb,
  'The year they want the property handed over. "as soon as possible" is 2026. "no rush" is any.'),
 ('exit_strategy',3,100,false,'enum',
  'Are you planning to hold and rent it out, or sell before handover?',
  '[{"label":"Hold and rent","value":"hold"},{"label":"Sell before handover","value":"flip"},{"label":"Not decided","value":"undecided"}]'::jsonb,
  '{"slot":"purpose","op":"in","value":["investment","both"]}'::jsonb,
  'Only relevant for investors. "flip", "resell", "assign" imply flip. "rental income", "long term" imply hold.'),
 ('visa_interest',3,110,false,'enum',
  'Is the golden visa part of what you''re looking for?',
  '[{"label":"Yes","value":"yes"},{"label":"No","value":"no"},{"label":"Tell me more","value":"wants_info"}]'::jsonb,
  '{"slot":"budget","op":"gte","value":2000000}'::jsonb,
  'Whether the UAE golden visa matters to them.'),
 ('prior_experience',3,120,false,'enum',
  'Have you bought property in Dubai before?',
  '[{"label":"Yes","value":"yes"},{"label":"No, first time","value":"no"}]'::jsonb,
  null::jsonb,
  'Whether they have bought Dubai property before. "I own in Marina" implies yes.'),
 ('decision_maker',3,130,false,'enum',
  'Is this decision just you, or is someone else involved?',
  '[{"label":"Just me","value":"solo"},{"label":"With my partner","value":"partner"},{"label":"With a business partner","value":"business"}]'::jsonb,
  null::jsonb,
  'Who else is involved in the decision. "my wife", "my husband" imply partner.')
) as s(slot_key, tier, priority, required, value_type, question_open, question_choices, condition, extraction_hint)
where m.code='AE';

-- ---------------------------------------------------------------------------
-- 3. Synthetic catalogue: 12 projects, 44 unit types (spec section 4.3)
-- ---------------------------------------------------------------------------

insert into lqs.projects (market_id, name, developer, area, sub_area, handover_quarter, handover_date, payment_plan, resale_threshold_pct, gross_yield_estimate, status, description)
select m.id, p.name, p.developer, p.area, p.sub_area, p.hq, p.hd::date, p.pp::jsonb, p.rt, p.gy, 'available', p.descr
from lqs.markets m,
(values
 ('Marina Vista II','Emaar','marina','Dubai Marina','2027-Q1','2027-09-30','{"label":"80/20","during_construction":80,"on_handover":20,"post_handover_months":0}',40,6.2,'Waterfront tower on the marina promenade with full-height glazing and a residents beach club.'),
 ('Creek Horizon Residences','Emaar','creek_harbour','Dubai Creek Harbour','2027-Q3','2027-09-30','{"label":"60/40","during_construction":60,"on_handover":40,"post_handover_months":0}',50,6.8,'Creek-facing towers with skyline and wildlife sanctuary views, next to the Creek Marina.'),
 ('Downtown Skyline Residences','Emaar','downtown','Downtown Dubai','2026-Q4','2026-12-31','{"label":"70/30","during_construction":70,"on_handover":30,"post_handover_months":0}',45,5.6,'Burj Khalifa and fountain views, walking distance to Dubai Mall.'),
 ('Bay Central Tower','Damac','business_bay','Business Bay','2026-Q2','2026-06-30','{"label":"80/20","during_construction":80,"on_handover":20,"post_handover_months":0}',35,7.1,'Canal-side tower aimed at short-let investors, fully fitted and furnished options.'),
 ('Marina Star','Damac','marina','Dubai Marina','2028-Q1','2028-03-31','{"label":"60/40","during_construction":60,"on_handover":40,"post_handover_months":24}',30,7.4,'Branded high-floor residences with a 24-month post-handover payment plan and the lowest resale threshold in the portfolio.'),
 ('Riverside Greens','Damac','dubai_south','Dubai South','2028-Q2','2028-06-30','{"label":"70/30","during_construction":70,"on_handover":30,"post_handover_months":0}',55,8.5,'Townhouse community near Al Maktoum airport and the Expo district, the highest projected yield in the portfolio.'),
 ('Hartland Waves','Sobha','creek_harbour','Sobha Hartland','2027-Q2','2027-06-30','{"label":"60/40","during_construction":60,"on_handover":40,"post_handover_months":0}',60,6.0,'Low-rise waterfront buildings inside a green master community with private schools on site.'),
 ('One Business Bay','Sobha','business_bay','Business Bay','2027-Q4','2027-12-31','{"label":"80/20","during_construction":80,"on_handover":20,"post_handover_months":0}',50,6.5,'Corner plot tower with canal frontage and a two-level residents club.'),
 ('Hills Edge Villas','Nakheel','dubai_hills','Dubai Hills Estate','2026-Q3','2026-09-30','{"label":"70/30","during_construction":70,"on_handover":30,"post_handover_months":0}',40,5.2,'Gated villa enclave backing onto the golf course, four and five bedroom layouts.'),
 ('JVC Garden Homes','Nakheel','jvc','Jumeirah Village Circle','2026-Q1','2026-03-31','{"label":"80/20","during_construction":80,"on_handover":20,"post_handover_months":0}',45,8.2,'Entry-price apartments and townhouses around a central park, popular with first-time investors.'),
 ('Hills Central Park','Meraas','dubai_hills','Dubai Hills Estate','2027-Q1','2027-03-31','{"label":"60/40","during_construction":60,"on_handover":40,"post_handover_months":0}',55,5.9,'Park-facing apartments over a retail podium, direct access to Dubai Hills Mall.'),
 ('Boulevard Heights','Meraas','downtown','Downtown Dubai','2028-Q3','2028-09-30','{"label":"70/30","during_construction":70,"on_handover":30,"post_handover_months":0}',35,5.0,'Branded ultra-prime residences on Sheikh Mohammed bin Rashid Boulevard with hotel service.')
) as p(name, developer, area, sub_area, hq, hd, pp, rt, gy, descr)
where m.code='AE';

insert into lqs.unit_types (project_id, bedrooms, bathrooms, size_sqft_min, size_sqft_max, price_from, price_to, service_charge_per_sqft, available_units)
select pr.id, u.bedrooms, u.bathrooms, u.smin, u.smax, u.pfrom, u.pto, u.sc, u.avail
from lqs.projects pr
join (values
 ('JVC Garden Homes',0,1,410,470,650000,890000,14.5,22),
 ('JVC Garden Homes',1,1,720,840,1050000,1450000,14.5,31),
 ('JVC Garden Homes',2,2,1120,1310,1550000,2100000,14.5,18),
 ('JVC Garden Homes',3,3,1880,2140,2400000,2950000,12.0,9),
 ('JVC Garden Homes',4,4,2450,2760,2600000,2980000,12.0,6),
 ('Riverside Greens',1,1,610,720,780000,1050000,11.5,26),
 ('Riverside Greens',2,2,1040,1220,1250000,1480000,11.5,20),
 ('Riverside Greens',3,3,1760,1980,1420000,1690000,10.0,14),
 ('Riverside Greens',4,4,2280,2540,1480000,1850000,10.0,8),
 ('Downtown Skyline Residences',0,1,480,540,1550000,1900000,22.0,12),
 ('Downtown Skyline Residences',1,2,780,910,2100000,2800000,22.0,17),
 ('Downtown Skyline Residences',2,3,1240,1480,3400000,4600000,22.0,11),
 ('Downtown Skyline Residences',3,4,1930,2260,5900000,7200000,22.0,5),
 ('Boulevard Heights',0,1,560,620,3100000,3800000,34.0,4),
 ('Boulevard Heights',1,2,980,1120,6200000,7400000,34.0,7),
 ('Boulevard Heights',2,3,1620,1880,8900000,10400000,34.0,5),
 ('Boulevard Heights',3,4,2410,2780,11000000,12000000,34.0,3),
 ('Marina Vista II',1,2,760,880,3200000,4500000,24.0,14),
 ('Marina Vista II',2,3,1180,1420,4900000,5900000,24.0,10),
 ('Marina Vista II',3,4,1840,2180,7800000,9200000,24.0,4),
 ('Marina Star',1,1,690,810,1750000,2300000,20.0,28),
 ('Marina Star',2,3,1290,1560,6500000,8900000,26.0,9),
 ('Marina Star',3,4,2040,2380,9400000,11200000,26.0,5),
 ('Marina Star',4,5,3120,3560,10500000,12000000,26.0,2),
 ('Bay Central Tower',0,1,430,500,900000,1150000,18.0,24),
 ('Bay Central Tower',1,2,740,870,1700000,2600000,18.0,29),
 ('Bay Central Tower',2,3,1160,1380,2700000,3400000,18.0,16),
 ('Bay Central Tower',3,4,1810,2090,4100000,5200000,18.0,7),
 ('One Business Bay',1,2,760,890,2300000,2900000,19.5,21),
 ('One Business Bay',2,3,1210,1440,3600000,4400000,19.5,13),
 ('One Business Bay',3,4,1890,2210,5400000,6600000,19.5,6),
 ('Creek Horizon Residences',1,1,700,820,1900000,2500000,21.0,25),
 ('Creek Horizon Residences',2,2,1130,1350,2600000,3300000,21.0,15),
 ('Creek Horizon Residences',3,3,1770,2050,4300000,5100000,21.0,8),
 ('Hartland Waves',0,1,440,510,1250000,1480000,17.0,19),
 ('Hartland Waves',1,2,730,860,1600000,2050000,17.0,23),
 ('Hartland Waves',2,3,1190,1400,2900000,3600000,17.0,12),
 ('Hartland Waves',3,4,1850,2160,4200000,5900000,17.0,6),
 ('Hills Edge Villas',3,4,2680,2980,4600000,5400000,9.5,11),
 ('Hills Edge Villas',4,5,3340,3720,5200000,5950000,9.5,7),
 ('Hills Edge Villas',4,6,4680,5240,8900000,10200000,9.5,3),
 ('Hills Central Park',1,1,710,830,1850000,2400000,16.5,20),
 ('Hills Central Park',2,3,1220,1460,3400000,5600000,16.5,12),
 ('Hills Central Park',3,4,1880,2190,6100000,7300000,16.5,5)
) as u(pname, bedrooms, bathrooms, smin, smax, pfrom, pto, sc, avail)
  on u.pname = pr.name;

-- ---------------------------------------------------------------------------
-- 4. Coverage check (spec section 4.3)
-- ---------------------------------------------------------------------------
-- Every budget bracket x every unit_type choice must return at least one match,
-- except 6M+ x Studio, which must return none so the empty-result path is exercised.
-- Expected: 19 rows with matches >= 1, and exactly one row (D_6M+, bedrooms 0) at 0.
--
-- with brackets(label, bmin, bmax) as (
--   values ('A_under1.5M',0::numeric,1500000::numeric),
--          ('B_1.5-3M',1500000,3000000),
--          ('C_3-6M',3000000,6000000),
--          ('D_6M+',6000000,999999999)
-- ), beds(b) as (values (0),(1),(2),(3),(4))
-- select br.label, be.b as bedrooms, count(u.id) as matches
-- from brackets br cross join beds be
-- left join lqs.unit_types u
--   on u.bedrooms = be.b
--  and u.price_from <= br.bmax
--  and coalesce(u.price_to, u.price_from) >= br.bmin
-- group by br.label, be.b
-- order by br.label, be.b;
