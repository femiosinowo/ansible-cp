CREATE TABLE doc
(
  id uuid NOT NULL,
  content character varying,
  type character varying(30),
  CONSTRAINT doc_pk PRIMARY KEY (id)
)
WITH (
  OIDS=FALSE
);

CREATE OR REPLACE FUNCTION upsert_doc(
    key uuid,
    doctype character varying,
    data character varying)
  RETURNS uuid AS
$BODY$
BEGIN
    LOOP
        -- first try to update the key
        UPDATE doc SET content = data, type = doctype WHERE id = key;
        IF found THEN
            RETURN key;
        END IF;
        -- not there, so try to insert the key
        -- if someone else inserts the same key concurrently,
        -- we could get a unique-key failure
        BEGIN
            INSERT INTO doc(id, type, content) VALUES (key, doctype, data);
            RETURN key;
        EXCEPTION WHEN unique_violation THEN
            -- Do nothing, and loop to try the UPDATE again.
        END;
    END LOOP;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;