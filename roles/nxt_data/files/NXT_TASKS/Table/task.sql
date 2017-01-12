-- Table: task

-- DROP TABLE task;

CREATE TABLE task
(
  pk serial NOT NULL,
  resource_identifier character varying(100),
  category character varying(50) NOT NULL,
  subcategory character varying(50),
  content bytea,
  status character varying(15) NOT NULL,
  date_modified timestamp with time zone NOT NULL,
  identifier character varying(50) NOT NULL,
  CONSTRAINT task_pkey PRIMARY KEY (pk)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE task
  OWNER TO administrator;
