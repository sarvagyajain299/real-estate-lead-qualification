-- v1.1.1 - ask for the email
--
-- Apply on top of 002. Data only, no DDL, safe to re-run.
--
-- The contact slot has always been able to hold an email - the extractor was
-- told to return {full_name, phone, email} from day one - but neither wording
-- of the question ever mentioned one, so lqs.leads.email was null on every
-- lead. Rather than spend a sixth question on it, the existing contact
-- question now asks for both. The fill rule is unchanged: phone OR email is
-- enough, so a lead who gives only a number still passes and is never
-- re-asked.

update lqs.slot_definitions
set question_open = 'What''s the best name and number for you, and an email if you have one?',
    extraction_hint = 'Extract {full_name, phone, email}. At least one of phone or email must be present to count as filled. Keep the phone in the format the lead wrote it, including country code if given. The lead may give a number and an email in the same message - capture both. Set email to null when they do not give one: never invent one, never guess it from their name, and never reuse an address from earlier in the conversation that was not theirs.'
where slot_key = 'contact';

-- The variant used when the channel already gave us a name (see 002).
update lqs.markets
set disclaimers = disclaimers::jsonb || jsonb_build_object(
  'contact_phone_only_line', jsonb_build_object(
    'en', 'And the best number for you, plus an email if you have one?',
    'ar', 'وما أفضل رقم للتواصل معك، وبريد إلكتروني إن توفر؟'
  )
);
