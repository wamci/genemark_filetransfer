-- export PGPASSWORD=gnmk
-- sudo -u postgres createuser --createdb rnd
-- sudo -u postgres createdb datastore
-- sudo -u postgres psql -c "alter user rnd with password 'gnmk'"
-- sudo -u postgres psql -c 'grant all privileges on database datastore to rnd'

CREATE SCHEMA genemark_filetransfer;
CREATE TABLE genemark_filetransfer.processing_logs
(
  id BIGSERIAL PRIMARY KEY,
  folder CHARACTER VARYING,
  bam_count INTEGER,
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
  processing_at TIMESTAMP WITHOUT TIME ZONE,
  finished_at TIMESTAMP WITHOUT TIME ZONE,
  attempts integer DEFAULT 0
)
WITH (
  OIDS=FALSE
);

CREATE TABLE genemark_filetransfer.animal_results
(
  id BIGSERIAL PRIMARY KEY,
  aliquot_id INTEGER,
  aliquot_id_alt INTEGER,
  animal_key INTEGER,
  birth_id CHARACTER VARYING,
  barcode CHARACTER VARYING,
  path CHARACTER VARYING,
  folder_name CHARACTER VARYING,
  file_name CHARACTER VARYING,
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
)
WITH (
  OIDS=FALSE
);

ALTER TABLE genemark_filetransfer.processing_logs ADD CONSTRAINT unique_folder_name UNIQUE (folder);
ALTER TABLE genemark_filetransfer.animal_results ADD CONSTRAINT unique_folder_name_with_file_name UNIQUE (folder_name, file_name);

