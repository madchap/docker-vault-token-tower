#!/usr/bin/env bash
set -e

# prepare the psql database and data

function create_database() {
	createdb $db -O vault
#	psql -d $db <<EOS
#GRANT ALL PRIVILEGES ON public.kv TO vault;
#EOS
}

function create_user() {
	psql <<EOS
CREATE USER $db_user with encrypted PASSWORD 'Vault';
ALTER USER $db_user with createuser;  
EOS
}


function create_table() {
	psql -U $db_user -d $db <<EOS
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
	psql -U $db_user -d $db <<EOS
insert into public.kv values (nextval('kv_id_seq'), 'poc', 'yes');
insert into public.kv values (nextval('kv_id_seq'), 'Vault', 'rules');
commit;
EOS

}

db_user=vault
db=vault_sandbox

create_user
create_database
create_table
populate_data


