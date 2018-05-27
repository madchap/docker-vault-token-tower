create database vault_sandbox;

create sequence public.kv_id_seq;

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

insert into public.kv values (nextval('kv_id_seq'), 'poc', 'yes');
insert into public.kv values (nextval('kv_id_seq'), 'Vault', 'rules');

commit;
