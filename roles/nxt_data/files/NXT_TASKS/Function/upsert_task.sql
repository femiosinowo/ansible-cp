-- Function: upsert_task(character varying, character varying, character varying, character varying, bytea, character varying, timestamp with time zone)

-- DROP FUNCTION upsert_task(character varying, character varying, character varying, character varying, bytea, character varying, timestamp with time zone);

CREATE OR REPLACE FUNCTION upsert_task(
    p_identifier character varying,
    p_category character varying,
    p_subcategory character varying,
    p_resource_identifier character varying,
    p_content bytea,
    p_status character varying,
    p_date_modified timestamp with time zone)
  RETURNS character varying AS
$BODY$

declare ident character varying :='';
declare subcat character varying :='';

BEGIN

IF (p_category = 'syndromic')
THEN 
	IF(p_subcategory = 'A08') -- replace an older, not sent A04/A08 message
	THEN
		select p.identifier, p.subcategory into ident, subcat from task p where status = 'new' and resource_identifier = p_resource_identifier and subcategory in ('A04', 'A08'); -- should be max 1 row
		IF (ident <> '')
		THEN 
			p_subcategory := subcat;
		END IF;	
	ELSE
		IF(p_subcategory = 'A03') -- generate A03 only once per encounter
		THEN
			select p.identifier into ident from task p where status <> 'new' and resource_identifier = p_resource_identifier and subcategory = p_subcategory; -- should be max 1 row
			IF(ident <> '')
			THEN
				RETURN null; -- ignore message
			END IF;
		END IF;

		select p.identifier into ident from task p where status = 'new' and resource_identifier = p_resource_identifier and subcategory = p_subcategory; -- should be max 1 row
	END IF;
ELSE 
	select p.identifier into ident  from task p where p.identifier = p_identifier;
END IF;

IF ( ident <> '' )
THEN
	update task set
	category = p_category,
	subcategory = p_subcategory,
	resource_identifier = p_resource_identifier,
	content = p_content,
	status = p_status,
	date_modified = p_date_modified
	where identifier = ident; -- update row with ident as identifier (ident may be different from p_identifier)

	RETURN ident;
ELSE
	insert into task
	(identifier, category, subcategory, resource_identifier, content, status, date_modified)
	values
	($1, $2, $3, $4, $5, $6, $7);

	RETURN $1;
END IF;

END
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION upsert_task(character varying, character varying, character varying, character varying, bytea, character varying, timestamp with time zone)
  OWNER TO administrator;
