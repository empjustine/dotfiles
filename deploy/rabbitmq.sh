#!/bin/sh

sudo apt-get install xsltproc

hg clone http://hg.rabbitmq.com/rabbitmq-codegen ~/repos/rabbitmq-codegen
hg clone http://hg.rabbitmq.com/rabbitmq-server ~/repos/rabbitmq-server

cd ~/repos/rabbitmq-server
make