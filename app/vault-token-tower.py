#!/usr/bin/env python
# -*- coding: utf-8 -*-
# /* ex: set filetype=python ts=4 sw=4 expandtab: */

from flask import Flask
# from flask import got_request_exception
from flask_restful import Resource, Api
from flask_jsonpify import jsonify
import hvac
import configparser
import os

# # generic error handling
# def log_exception(sender, exception, **extra):
#     print("Got an exception from {} during processing: {}".format(sender, exception))
#
#
# errors = {
#     'VaultIsSealed': {
#         'message': "The Vault is sealed.",
#         'status': 500
#     }
# }



class get_token(Resource):
    """
    Test class to see what the token value looks like
    """
    def get(self):
        if not vc.is_sealed():
            result = {'token': vc.lookup_token()}
            return jsonify(result)
        else:
            print("Vault is sealed. Cannot perform request.")
            return jsonify({'vault_status': 'Vault is sealed'})


class get_roleid(Resource):
    """
    equivalent of `vault read auth/approle/role/<your_role>/role-id
    """
    def get(self, role_name):
        if not vc.is_sealed():
            role_info = vc.read("auth/approle/role/{}/role-id".format(role_name))
            return jsonify(role_id=role_info['data']['role_id'])
        else:
            print("Vault is sealed. Cannot perform request.")
            return jsonify({'vault_status': 'Vault is sealed'})


class get_wrap_token(Resource):
    """
    Equivalent of `vault write -wrap-ttl=60s -f auth/approle/role/<your_role>/secret-id`
    """
    def post(self, role_name):
        if not vc.is_sealed():
            #TODO flexible ttl
            secret_info = vc.write("auth/approle/role/{}/secret-id".format(role_name), wrap_ttl='60s')
            print(secret_info)
            return jsonify(wrap_token=secret_info['wrap_info']['token'])
        else:
            print("Vault is sealed. Cannot perform request.")
            return jsonify({'vault_status': 'Vault is sealed'})


def get_vault_status():
    print("Vault status:")
    print("* Vault is initialized? {}".format(vc.is_initialized()))
    print("* Vault is sealed? {}".format(vc.is_sealed()))

    # while vc.is_sealed():
    #     print("Vault is currently sealed. Checking again in 10s.")
    #     time.sleep(10)


app = Flask(__name__)
# got_request_exception.connect(log_exception, app)
# api = Api(app, errors=errors)
api = Api(app)

config = configparser.ConfigParser()
config.read(os.path.join(os.path.dirname(__file__), 'vault-token-tower.conf'))

# initialize vault client
vc = hvac.Client(url=config.get("vault", "vault_addr"),
                 token=open('/app/token', 'r').read().strip())

get_vault_status()

# build endpoints
api.add_resource(get_token, '/token')
api.add_resource(get_roleid, '/roleid/<role_name>')
api.add_resource(get_wrap_token, '/wraptoken/<role_name>')

app.run(
        host=config.get('app', 'host'),
        port=config.getint('app', 'port'),
        debug=config.getboolean('app', 'debug')
    )