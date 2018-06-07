#!/usr/bin/env bash
#
# Test which SSL ciphers are enabled on a device
#
# Revision: 2017040400
#
# Note this script can be very noisy, as it makes multiple connection attempts,
# caution should be taken when running against equipment.  Add delay or limit
# the list of ciphers to test.

# get command line parameters
CIPHERS=()

while (( "$#" )); do
  if [ "$1" = "--port" ] ; then
    shift
    PORT="$1"
  elif [ "$1" = "--delay" ] ; then
    shift
    DELAY="$1"
  elif [[ "$1" = "--"* ]] ; then
    # unrecognized parameter
    ERROR=1
  elif [ "$SERVER" = "" ] ; then
    SERVER="$1"
  else
    CIPHERS+=("$1")
  fi
  shift
done

PORT="${PORT:-443}"
DELAY="${DELAY:-1}"

if [ "$SERVER" = "" -o "$PORT" = "" -o "$ERROR" = 1 ] ; then
  cat<<END
Command line utility to test which SSL ciphers are accepted on a device.
Note this script can be very noisy, as it makes multiple connection attempts,
caution should be taken when running against equipment.  Add delay or limit
the list of ciphers to test.


SYNTAX:

$0 <hostname> [--port <port>] [--delay <delay>] [<cipher list>]


DESCRIPTION:

--port		Optionally specify a port to connect to.
		The default port is 443.

--delay		Optionally specify the delay between each chec.
		The default delay is 1 second.

cipher list	List of ciphers to test.  The default is to pull
                the cipher list from $(openssl version).


Examples:

$0 host.example.com
$0 host.example.com --port 443 --delay 0 DHE-RSA-AES256-SHA AES256-SHA AES128-SHA DES-CBC3-SHA

END

  exit
fi



# OpenSSL requires the port number.
if [ ${#CIPHERS[@]} = 0 ] ; then
  echo Obtaining cipher list from $(openssl version).
  CIPHERS=$(openssl ciphers 'ALL:eNULL' | sed -e 's/:/ /g')
fi

echo Testing $SERVER:$PORT

for cipher in ${CIPHERS[@]}
do
echo -n Testing $cipher...

result=$(echo -n | openssl s_client -cipher "$cipher" -connect $SERVER:$PORT 2>&1)
if [[ "$result" =~ ":error:" ]] ; then
  error=$(echo -n $result | cut -d':' -f6)
  echo NO \($error\)
else
  if [[ "$result" =~ "Cipher is ${cipher}" || "$result" =~ "Cipher    :" ]] ; then
    echo YES
  else
    echo UNKNOWN RESPONSE
    echo $result
  fi
fi
sleep $DELAY
done
