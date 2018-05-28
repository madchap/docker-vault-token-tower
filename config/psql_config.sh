#!/usr/bin/env bash
set -e

# prepare the psql database and data

function create_database() {
	createdb $db
}

function create_user() {
	psql -d $db <<EOS
CREATE USER vault with encrypted PASSWORD 'Vault'
EOS
}


function create_table() {
	psql -d $db <<EOS
CREATE sequence kv_id_seq;

CREATE TABLE public.kv
(
    id integer NOT NULL DEFAULT nextval('kv_id_seq'::regclass),
    key text COLLATE pg_catalog."default",
    value text COLLATE pg_catalog."default",
    CONSTRAINT kv_pkey PRIMARY KEY (id)	
)
WITH (
    OIDS = FALSE
);
EOS
}

function populate_data() {
	psql -d $db <<EOS
insert into public.kv values (nextval('kv_id_seq'), 'poc', 'yes');
insert into public.kv values (nextval('kv_id_seq'), 'Vault', 'rules');
commit;
EOS

}

db=vault_sandbox

create_database
create_user
create_table
populate_data


