#!/bin/bash

set -ex

export PGHOST=localhost
export PGDATABASE=kv
export PGUSER=postgres
export PGPASSWORD=yourpass

PSQL="/usr/bin/psql -X --echo-all"

# create database vault_sandbox
$PSQL <<EOS

create sequence public.kv_id_seq;

create database vault_sandbox;

CREATE TABLE vault_sandbox.kv
(
    id integer NOT NULL DEFAULT nextval('kv_id_seq'::regclass),
    key text COLLATE pg_catalog."default",
    value text COLLATE pg_catalog."default",
    CONSTRAINT kv_pkey PRIMARY KEY (id)
)
WITH (
    OIDS = FALSE
);

insert into vault_sandbox.kv values (nextval('kv_id_seq'), 'poc', 'yes');
insert into vault_sandbox.kv values (nextval('kv_id_seq'), 'Vault', 'rules');

commit;
EOS
