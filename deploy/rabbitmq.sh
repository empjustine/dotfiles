#!/bin/sh

sudo apt-get install xsltproc

hg clone http://hg.rabbitmq.com/rabbitmq-codegen ~/build/rabbitmq-codegen
hg clone http://hg.rabbitmq.com/rabbitmq-server ~/build/rabbitmq-server

cd ~/build/rabbitmq-server
make