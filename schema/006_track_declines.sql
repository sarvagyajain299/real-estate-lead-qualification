-- v1.3.0 - remember that a lead said no
--
-- Apply on top of 005_conversational_replies.sql. One column, safe to re-run.
--
-- WHY
-- Decide Next Step counts declines to decide whether it may put times in front
-- of the lead again. Counting bookings rows with status 'declined' only works
-- when an offer was open at the time. A lead who says "I don't want a meeting"
-- at question two has no open offer, so nothing was recorded, and the bot
-- offered them one anyway the moment qualification finished.
--
-- The counter lives on the conversation instead, so a refusal is remembered
-- whether or not there was an offer to refuse.

alter table lqs.conversations
  add column if not exists booking_declines int not null default 0;

comment on column lqs.conversations.booking_declines is
  'How many times this lead has turned a meeting down. One decline stops the bot offering unprompted; it will still offer if the lead asks (intent booking_intent).';
