-- v1.1.0 - shorter, warmer conversation
--
-- Apply on top of 001_lqs_schema_and_seed.sql. Data only: no DDL, nothing here
-- changes a table shape, so it is safe to re-run.

-- 1. Offer the meeting once the five essentials are in, instead of after eight
--    questions. Tier-1 asking is never gated by this number, so all five
--    required slots are still always asked; max_questions only caps the
--    optional depth questions that follow.
update lqs.markets
set thresholds = jsonb_set(thresholds::jsonb, '{max_questions}', '5'::jsonb);

-- 2. Telegram hands us a display name at first contact, so the contact slot
--    should ask only for the number. Decide Next Step swaps this line in when
--    lqs.leads.full_name is already set.
update lqs.markets
set disclaimers = disclaimers::jsonb || jsonb_build_object(
  'contact_phone_only_line', jsonb_build_object(
    'en', 'And the best number to reach you on?',
    'ar', 'وما أفضل رقم للتواصل معك؟'
  )
);

-- 3. Capture-only slot. A lead who opens with "a project at Emaar Beachfront"
--    has already told us where they are looking. Nothing was recording that,
--    so the bot went on to ask which area they liked. This slot is tier 2 and
--    last by priority, so the ladder never reaches it as a question - the
--    extractor just fills it from whatever the lead says.
insert into lqs.slot_definitions
  (market_id, deal_type, slot_key, tier, priority, required, value_type,
   question_open, question_choices, condition, extraction_hint, active)
select m.id, 'offplan', 'project_interest', 2, 999, false, 'text',
  'Is there a particular project or building you had in mind?',
  null, null,
  'Capture any named development, tower, community or master project the lead mentions, verbatim as they wrote it but with obvious spelling corrected (for example "emaar bechfront" is "Emaar Beachfront"). This is never asked as a question - only fill it when the lead names a place unprompted. Leave it out when they only describe a generic area.',
  true
from lqs.markets m
on conflict do nothing;

-- 4. ...and do not ask which area when they have already named a place. Needs
--    the `empty` operator added to conditionSatisfied in this version.
update lqs.slot_definitions
set condition = '{"op":"empty","slot":"project_interest"}'::jsonb
where slot_key = 'area_preference';

-- 5. The extractor was being shown the budget brackets and was picking the
--    nearest one instead of reading the number. "1M usd" came back as the
--    "Under 1.5M AED" bracket, which also destroyed the currency and stopped
--    the FX conversion from ever firing. Core no longer sends choices for
--    non-enum slots; this makes the hint say so as well.
update lqs.slot_definitions
set extraction_hint = 'Return {min, max, currency}. "around 3 million" means {min: 2700000, max: 3300000}. "up to 2M" means {min: 0, max: 2000000}. "1M" alone means {min: 900000, max: 1100000}. Record the number the lead actually said - never round it to a bracket or a round figure of your own. If they name a currency (usd, dollars, $, gbp, pounds, eur, euros, inr, rupees) set currency to that ISO code, not AED. Only default to AED when no currency is named.'
where slot_key = 'budget';

-- 6. One-off repair of the value that bug produced on the live test lead.
update lqs.qualification
set value = '{"min":3305250,"max":4039750,"currency":"AED","fx_applied":true,"original":{"currency":"USD","min":900000,"max":1100000}}'::jsonb,
    updated_at = now()
where slot_key = 'budget'
  and value::jsonb = '{"max":1500000,"min":0,"currency":"AED"}'::jsonb;
