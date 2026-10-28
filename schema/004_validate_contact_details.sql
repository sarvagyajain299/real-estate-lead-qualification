-- v1.2.0 - validate the contact details
--
-- Apply on top of 003. The validation itself lives in the Validate Extraction
-- Code node of LQS - Subworkflow: extract facts and in the Apply Upserts query
-- of LQS - Qualification: save answers; see workflows/. The only schema object
-- added here is the view.

-- The mailing list v1.1.1 was collecting addresses for. Reading lqs.leads
-- directly works just as well; this exists so the list has one obvious name.
create or replace view lqs.mailing_list as
select l.id as lead_id,
       l.full_name,
       l.email,
       l.phone,
       l.status,
       l.created_at,
       m.code as market
from lqs.leads l
join lqs.markets m on m.id = l.market_id
where l.email is not null and l.email <> ''
order by l.created_at desc;

-- Nothing repairs existing rows: lqs.leads.email was null on every lead before
-- v1.1.1 and no malformed address was ever stored, so there is nothing to clean.
-- If one ever does get through, this finds it:
--   select id, email from lqs.leads
--   where email is not null and email not like '%_@_%._%';
