#!/bin/bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ../config/tls.key \
  -out ../config/tls.crt \
  -subj "/CN=vikas.apperfect.com/O=example"