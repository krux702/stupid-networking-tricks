#!/bin/bash

# Script that manages starting / reconnecting to screen instances

if [ ! -O `tty` ] ; then
  # if we're running under su, we need to own our terminal so start a null script session
  script -c "$0 $1 $2" /dev/null

else
  # run as normal
  if [ ! -f ~/.screenmultirc ] ; then
    # initialize base screen config
    cat <<END > ~/.screenmultirc
defscrollback 10000
multiuser on
acladd $USER

hardstatus alwayslastline
hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %d/%m %{W}%c %{g}]'
END

  fi

  if [ ! -f ~/.screensinglerc ] ; then
    # initialize base screen config
    cat <<END > ~/.screensinglerc
defscrollback 10000

hardstatus alwayslastline
hardstatus string '%{= kG}[ %{G}%H %{g}][%= %{= kw}%?%-Lw%?%{r}(%{W}%n*%f%t%?(%u)%?%{r})%{w}%?%+Lw%?%?%= %{g}][%{B} %d/%m %{W}%c %{g}]'
END

  fi

  if [ "$1" == "m" -a "$2" != "" ] ; then
    if [ "`screen -list | grep terminal.$2 | awk '{ print $1 }'`" != "" ] ; then
      echo creating multiuser screen session $2
      screen -A -x -c .screenmultirc -S terminal.$2
    else
      echo attaching to multiuser screen session $2
      screen -A -d -c .screenmultirc -RR -S terminal.$2
    fi
  elif [ "$1" != "" ] ; then
    echo single user screen session $1
    screen -A -d -c .screensinglerc -RR -S terminal.$1
  else
    if [ `screen -list | grep -c terminal` == "0" ] ; then
      # no other sessions, so create one
      echo creating single user screen session
      screen -A -d -c .screensingleirc -RR -S terminal.1  
    elif [ `screen -list | grep -c terminal` == "1" ] ; then
      # only one session so disconnect all other sessions and connect to it
      screen -A -d -c .screensinglerc -RR
    else
      echo "Multiple screen sessions exist.  Run \"$0 <session number>\" to re-attach."
      echo
      echo -n "sessions available: "
      for name in `screen -list | grep terminal | sed -E "s/^.*terminal\.([^\t]+).*$/\1/"` ; do echo -n "$name " ; done ; echo
    fi
  fi
fi
