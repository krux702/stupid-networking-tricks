#!/bin/bash
#
# simplifies creation of DNS record through IPA command line
#
# Revision: 2016010500
#
# This can handle adding A records and CNAME records.
# It will not add an A record if the IP address is in an invalid format
# It automatically creates the reverse record for internal IP space
# It will not add a CNAME record if the record it is referencing does not exist
# Has options to handle overwritting forward and reverse records
#
# Requires the "ipa" command, so is run on the IPA servers

# get command line parameters
while (( "$#" )); do
  if [ "$1" = "--overwrite" ] ; then
    OVERWRITE=1
  elif [ "$1" = "--overwrite-reverse" ] ; then
    OVERWRITE_REVERSE=1
  elif [[ "$1" = "--"* ]] ; then
    # unrecognized parameter
    ERROR=1
  elif [ "$record_name" = "" ] ; then
    record_name="$1"
  elif [ "$record_type" = "" ] ; then
    record_type="`echo $1 | tr '[a-z]' '[A-Z]'`"
  elif [ "$record_data"	= "" ]	; then
    record_data="$1"
  elif [ "$zone" = "" ] ; then
    zone="$1"
  fi
  shift
done
zone="${zone:-example.com}"


if [ "$record_name" = "" -o "$record_type" = "" -o "$record_data" = "" -o "$ERROR" = 1 ] ; then
  cat<<END
Command line utility to simplify and automate updating IPA DNS records from the command line.
Everything this does can be handled by the "ipa" command, but this adds some syntax, error
checking, and dependency checking before making changes.  It also a format similar to standard
DNS zone records for command line input.  

SYNTAX:

$0 <record_name> <record_type> <record_data> [<zone>] [--overwrite] [--overwrite-reverse]

Examples:

$0 hosta A 10.10.0.254
$0 hostb CNAME hostb-loop0.${zone}.

END

  exit
fi


# check for kerberos ticket
if ! klist 2> /dev/null > /dev/null ; then
  # no kerberos ticket found, create one
  kinit
fi


if [ "$OVERWRITE" = "1" ] ; then
  # check for record
  if ipa dnsrecord-find $zone --name=$record_name > /dev/null ; then
    ipa dnsrecord-del $zone $record_name --del-all  
  fi
fi


# search for record, and try to add if it does not exist
if ! ipa dnsrecord-find $zone --name=$record_name > /dev/null ; then

  # Add A record
  if [ "$record_type" = "A" ] ; then
    bad_ip=0
    IFS=. read -a ip_addr <<< "$record_data"
    for (( i=0 ; i < ${#ip_addr[@]} ; i++ )) ; do
      printf "%g" "${ip_addr[$i]}" &> /dev/null
      if [[ $? != 0 ]] ; then
        # non-numeric
        bad_ip=1
      elif [ "${ip_addr[$i]}" -le 0 -o "${ip_addr[$i]}" -ge 255 ] ; then
        # invalid range
        bad_ip=1
      fi
    done
    if [ "$i" -ne 4 ] ; then
      # incorrect number of octets
      bad_ip=1
    fi
    if [ "$bad_ip" -eq 1 ] ; then
      echo "Error adding $record_name $record_type, Invalid IP address: $record_data"
    else
      # check for our IP space
      if [ ${ip_addr[0]} -eq 10 ] ; then
        options="--a-create-reverse"

        # check for reverse
        revzone="${ip_addr[2]}.${ip_addr[1]}.${ip_addr[0]}.in-addr.arpa."
        if ipa dnsrecord-find $revzone ${ip_addr[3]} >/dev/null ; then
          # reverse record exists
          if [ "$OVERWRITE_REVERSE" = "1" ] ; then
            echo "Removing previous PTR Record for ${ip_addr[3]} in $revzone"
            ipa dnsrecord-del $revzone ${ip_addr[3]} --del-all >/dev/null
          else
	    echo "Warning: PTR Record for ${ip_addr[3]} exists in $revzone"
            options=""
          fi
        fi

      else
        options=""
      fi

      # A record good ok to add
      echo "ipa dnsrecord-add $zone $record_name --a-rec $record_data $options"
      ipa dnsrecord-add $zone $record_name --a-rec $record_data $options

    fi
  fi

  if [ "$record_type" = "CNAME" ] ; then
    cname_host="`echo $record_data | sed 's/\./ /' | awk '{ print $1 }'`"
    cname_zone="`echo $record_data | sed 's/\./ /' | sed 's/\.$//' | awk '{ print $2 }'`"
    if ipa dnsrecord-find $cname_zone --name=$cname_host > /dev/null ; then
      # CNAME reference found, ok to add
      echo "ipa dnsrecord-add $zone $record_name --cname-rec $record_data"
      ipa dnsrecord-add $zone $record_name --cname-rec $record_data

    else
      echo "No forward record for $record_data found, not adding $record_name"
    fi
  fi
else
  echo Record for $record_name exists
fi

