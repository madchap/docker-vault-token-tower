#!/usr/bin/env python
# -*- coding: utf-8 -*-
# /* ex: set filetype=python ts=4 sw=4 expandtab: */

import hvac
import psycopg2
import requests

# you can launch me by hand


def get_data(url):
    r = requests.get(url=url)
    return r.json()


def post_data(url):
    r = requests.post(url=url)
    return r.json()


def unwrap(wrappedtoken):
    vc.unwrap(wrappedtoken['wrap_token'])


def approle_login():
    pass


# get psql creds
def get_psql_creds():
    pass

# login to db and perform select
def select_from_table():
    pass


if __name__ == "__main__":
    vtt = "http://localhost:5000"
    rolename = "meetup-demo-role"
    roleid_ep = "/roleid"
    wraptoken_ep = "/wraptoken"

    print("Welcome to the witness app.")

    vc = hvac.Client(url="http://localhost:8200")

    # get roleid
    roleid = get_data("{}{}/{}".format(vtt, roleid_ep, rolename))
    print(roleid)

    # get wrapped token
    wraptokenid = post_data("{}{}/{}".format(vtt, wraptoken_ep, rolename))
    print(wraptokenid)

    # unwrap token to get secretid
    unwrapped_data = unwrap(wraptokenid)
    print(unwrapped_data)

    # login to approle with roleid and secretid

    # get psql credentials from database/creds/vault_sandbox

    # login to database and select records