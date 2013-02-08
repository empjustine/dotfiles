#!/bin/sh

sudo mkdir -p /media/waik
sudo mount ~/Downloads/KB3AIK_EN.iso /media/waik

mkdir /tmp/wAIKX86.msi/ /tmp/WinPE.cab/
cd /tmp/wAIKX86.msi/
extract /media/waik/wAIKX86.msi