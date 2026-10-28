-- v1.3.0 - a deferral is not an answer
--
-- Apply on top of 006_track_declines.sql. Data only, safe to re-run.
--
-- WHY
-- The lead was asked how they would pay and said "I will tell later". The
-- extractor mapped that onto the enum value `unsure` ("Not sure yet"), which is
-- a filled slot, so the ladder moved on and the brief told the agent the lead
-- had not decided how to pay. They had not said that. They said they would tell
-- us later, which is a different thing and is worth the agent asking again.
--
-- Leaving the slot out entirely makes it get re-asked once, and if it is dodged
-- twice it lands in the brief's Not covered block, which is where it belongs.

update lqs.slot_definitions
set extraction_hint = 'Classify how they intend to pay. "loan", "finance", "bank" imply mortgage. "instalments", "plan" imply developer_plan. Only return unsure when they actually say they have not decided. A deferral is not an answer: "I will tell you later", "later", "I will let you know", "not right now", "we can discuss that" mean you leave this slot out of the response entirely rather than recording unsure.'
where slot_key = 'payment_method';

-- The same trap exists on every enum with a "not sure" or "open to" option: a
-- lead putting the question off is not the same as a lead with no preference.
update lqs.slot_definitions
set extraction_hint = extraction_hint || ' A deferral is not an answer - if they say they will tell you later, leave this slot out rather than choosing an option for them.'
where slot_key in ('timeline', 'unit_type', 'area_preference', 'handover_preference', 'exit_strategy')
  and extraction_hint not like '%A deferral is not an answer%';
