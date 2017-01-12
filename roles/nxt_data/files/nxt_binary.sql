CREATE TABLE doc
(
  id uuid NOT NULL,
  size integer,
  doc_oid oid NOT NULL,
  mime_type character varying,
  created timestamp with time zone NOT NULL DEFAULT ('now'::text)::timestamp without time zone,
  owner character varying(50),
  hash character varying(80),
  is_compressed boolean NOT NULL,
  CONSTRAINT doc_pk PRIMARY KEY (id),
  CONSTRAINT doc_unique_oid UNIQUE (doc_oid)
)
WITH (
  OIDS=FALSE
);