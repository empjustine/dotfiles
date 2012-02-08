#!/bin/sh

sudo apt-get install xsltproc

hg clone http://hg.rabbitmq.com/rabbitmq-codegen ~/.rabbitmq/rabbitmq-codegen
hg clone http://hg.rabbitmq.com/rabbitmq-server ~/.rabbitmq/rabbitmq-server
cd ~/.rabbitmq/rabbitmq-server
make