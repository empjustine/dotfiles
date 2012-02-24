#!/bin/sh
#notify-send -i mail 'GMail' `echo $1 | sed 's/mailto://'`
#/usr/bin/chromium-browser -app="https://mail.google.com/mail?view=cm&tf=0&to=`echo $1 | sed 's/mailto://'`"
#/usr/bin/firefox -new-tab="https://mail.google.com/mail?view=cm&tf=0&to=`echo $1 | sed 's/mailto://'`"
/usr/bin/sensible-browser "https://mail.google.com/mail?view=cm&tf=0&to=`echo $1 | sed 's/mailto://'`"
