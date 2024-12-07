#!/bin/sh
set -eu

instance_name=vicmet01
instance_addr=$(incus list -c 4 -f csv ${instance_name} | cut -d ' ' -f 1)
incus config device add ${instance_name} http proxy listen=tcp:0.0.0.0:3000 connect=tcp:${instance_addr}:3000 bind=host
