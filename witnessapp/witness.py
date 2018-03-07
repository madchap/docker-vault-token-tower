#!/usr/bin/env python
# -*- coding: utf-8 -*-
# /* ex: set filetype=python ts=4 sw=4 expandtab: */

import hvac
import psycopg2
import requests
import sys

# you can launch me by hand


def get_data(url):
    r = requests.get(url=url)
    return r.json()['role_id']


def post_data(url):
    r = requests.post(url=url)
    return r.json()['wrap_token']


def unwrap(wrappedtoken):
    r_data = vc.unwrap(wrappedtoken)
    return r_data['data']['secret_id']


def approle_login(roleid, secretid):
    return vc.auth_approle(roleid, secretid)


def get_psql_creds():
    return vc.read(psql_vault_creds_ep)


def delete_psql_creds(leaseid):
    vc.revoke_secret(leaseid)


def login_to_psql(dyn_user, dyn_passwd):
    try:
        return psycopg2.connect("dbname={} host='{}' user='{}' password='{}'".format(psql_db, psql_host, dyn_user, dyn_passwd))
    except:
        print("Cannot connect to postgres database {}".format(psql_db))


def select_from_table():
    cur = conn.cursor()
    cur.execute("""select * from {}""".format(psql_table))
    rows = cur.fetchall()
    print("\nRows returned:")
    for row in rows:
        print(" ", row[0], row[1], row[2])


if __name__ == "__main__":
    # vault-tower url
    vtt = "http://localhost:5000"

    # vault url
    vault_url = "http://localhost:8200"

    # endpoints info
    rolename = "witness-role"
    roleid_ep = "/roleid"
    wraptoken_ep = "/wraptoken"

    # postgres info
    psql_db = "vault_sandbox"
    psql_table = "kv"
    psql_host = "localhost"

    psql_vault_creds_ep = "database/creds/appro"

    print("Welcome to the witness app.")
    print("I will use my companion vault-tower at {}, Vault at {} and use role {}.\n".format(vtt, vault_url, rolename))

    vc = hvac.Client(url="{}".format(vault_url))
    if vc.is_sealed():
        print("Vault is sealed. Cannot perform.")
        sys.exit(-1)

    # get roleid
    roleid = get_data("{}{}/{}".format(vtt, roleid_ep, rolename))
    print("Role id: {}".format(roleid))

    # get wrapped token
    wraptokenid = post_data("{}{}/{}".format(vtt, wraptoken_ep, rolename))
    print("Wrapped token: {}".format(wraptokenid))

    # unwrap token to get secretid
    unwrapped_secret = unwrap(wraptokenid)
    print("Secret id: {}".format(unwrapped_secret))

    # login to approle with roleid and secretid
    r_login = approle_login(roleid, unwrapped_secret)
    shiny_token = r_login['auth']['client_token']
    print("Token: {}".format(shiny_token))

    # make sure our vault client object is aware of that shiny token
    vc.token = shiny_token

    # get psql credentials from database/creds/vault_sandbox
    psql_creds = get_psql_creds()
    print("Postgres dynamic creds: {}".format(psql_creds))
    psql_user = psql_creds['data']['username']
    psql_passwd = psql_creds['data']['password']
    psql_creds_lease_id = psql_creds['lease_id']

    # login to database
    try:
        conn = login_to_psql(psql_user, psql_passwd)
    except:
        print("Deleting role in postgreSQL, as they seem useless.")
        delete_psql_creds(psql_creds_lease_id)

    # select records
    select_from_table()

    # revoking lease, thereby deleting creds
    print("\nI am done! I can now delete my non-needed postgreSQL credentials.")
    print("\nMy lease id is {}, and that's all I need.".format(psql_creds_lease_id))

    # revoke the lease for the creds just used
    delete_psql_creds(psql_creds_lease_id)
