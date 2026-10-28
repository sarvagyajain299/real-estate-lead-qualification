-- v1.3.0 - conversational replies
--
-- Apply on top of 004_validate_contact_details.sql. Data + one nullable column;
-- nothing here changes an existing table's shape destructively, so it is safe to
-- re-run.
--
-- WHY
-- `question_open` was doing two jobs: telling the composer what to find out, and
-- being the literal words sent to the lead. The composer prompt called it "THE
-- APPROVED QUESTION", so the model reproduced it verbatim - including the
-- dangling "this" in "Are you looking at this as an investment", which refers to
-- nothing when the lead has only said "Hi". Splitting the two jobs is the fix:
-- `question_goal` says what to find out, `question_open` stays as the fallback
-- wording used only when the model fails.

-- 1. What each slot is for, in plain words. The composer writes its own sentence
--    from this; it never sees `question_open` except as a fallback.
alter table lqs.slot_definitions add column if not exists question_goal text;

update lqs.slot_definitions set question_goal = g.goal
from (values
  ('purpose',              'whether they are buying as an investment or somewhere to live in themselves'),
  ('budget',               'roughly how much they are looking to spend - a range is fine'),
  ('payment_method',       'how they plan to pay: cash, a mortgage, or a developer payment plan'),
  ('timeline',             'how soon they are looking to buy'),
  ('contact',              'the best phone number to reach them on, and an email address if they have one'),
  ('unit_type',            'how many bedrooms they are after'),
  ('area_preference',      'which parts of Dubai they are interested in, or whether they are open to suggestions'),
  ('residency',            'whether they live in the UAE, elsewhere in the GCC, or overseas'),
  ('handover_preference',  'how soon they need the property handed over'),
  ('exit_strategy',        'whether they plan to hold and rent it out, or sell before handover'),
  ('visa_interest',        'whether the UAE golden visa is part of what they want'),
  ('prior_experience',     'whether they have bought property in Dubai before'),
  ('decision_maker',       'whether they are deciding on their own or with someone else'),
  ('project_interest',     'which project or building they have in mind')
) as g(slot_key, goal)
where lqs.slot_definitions.slot_key = g.slot_key;

-- 2. Fallback wording for the two new turns. These are only ever sent when the
--    composer errors or its output fails validation - they are not the normal
--    path for anything.
update lqs.markets
set disclaimers = disclaimers::jsonb || jsonb_build_object(
  'decline_ack_line', jsonb_build_object(
    'en', 'No problem, no meeting for now. Ask me anything you like about the projects.',
    'ar', 'لا مشكلة، لا داعي للموعد الآن. اسألني عما تريد معرفته عن المشاريع.'
  ),
  'declined_twice_line', jsonb_build_object(
    'en', 'Understood, I will leave the meeting there. I am still here if you want to know anything about the projects.',
    'ar', 'حسنًا، لن أعود لموضوع الموعد. أنا هنا إن أردت معرفة أي شيء عن المشاريع.'
  )
) where code = 'AE';

-- 3. Keep the lead's own words for the budget alongside the widened search band.
--    The extractor widens "4 million" to 3.6M-4.4M so the catalogue search has a
--    band to work with; that number then got read back to the lead as if they had
--    said it. The band stays internal, `stated_text` is what a human sees.
update lqs.slot_definitions
set extraction_hint = 'Return {min, max, currency, stated_text}. stated_text is the budget exactly as the lead wrote it, for example "4 million" or "around 2.5m" - copy their words, never a number you worked out. "around 3 million" means {min: 2700000, max: 3300000}. "up to 2M" means {min: 0, max: 2000000}. "1M" alone means {min: 900000, max: 1100000}. Record the number the lead actually said - never round it to a bracket or a round figure of your own. If they name a currency (usd, dollars, $, gbp, pounds, eur, euros, inr, rupees) set currency to that ISO code, not AED. Only default to AED when no currency is named.'
where slot_key = 'budget';

-- 4. A lead who says no to a meeting gets their open offer closed rather than
--    left dangling as 'offered'. `status` has no check constraint, so this needs
--    no DDL - it is recorded here because Decide Next Step now reads it.
comment on column lqs.bookings.status is
  'offered | confirmed | declined | cancelled. declined is set when the lead refuses the meeting; it clears awaitingChoice so the bot stops trying to read a slot choice out of every message.';
