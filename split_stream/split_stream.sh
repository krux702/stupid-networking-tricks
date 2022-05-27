#!/bin/bash

if [ "$1" == "" ] ; then
  cat <<END
split stream - splits a packet capture into its individual TCP and UDP streams for analysis.

syntax: ./split_stream.sh <pcap_file> [output_dir]

END
  exit
fi

PCAP="$1"
OUTPUT_DIR=${PCAP}_streams
OUTPUT_DIR=${2:-$OUTPUT_DIR}

if [[ ! -d $OUTPUT_DIR && -f $OUTPUT_DIR ]] ; then
  echo "Error: $OUTPUT_DIR must not be a file"
  exit
else
  mkdir -p $OUTPUT_DIR
fi

FILE_TYPE="`file ${PCAP} | grep 'capture file'`"
if [ "$FILE_TYPE" = "" ] ; then
  echo "Error: $PCAP is not a pcap file"
  file $PCAP
  exit
fi

TCPSTR=`tshark -nr ${PCAP} -q -z conv,tcp | grep -c "<->"`
TCPSESS="$(($TCPSTR-1))"

for i in $(seq 0 $TCPSESS); do
  echo extracting TCP stream $i
  tshark -r ${PCAP} -z follow,tcp,raw,$i | \
    grep -E "^(\s+|)[0-9a-f]*$" | \
    tr -d '=\r\n\t' | xxd -r -p > $OUTPUT_DIR/session_tcp_$i.bin
done

UDPSTR=`tshark -nr ${PCAP} -q -z conv,udp | grep -c "<->"`
UDPSESS="$(($UDPSTR-1))"

for i in $(seq 0 $UDPSESS); do
  echo extracting UDP stream $i
  tshark -r ${PCAP} -z follow,udp,raw,$i | \
    grep -E "^(\s+|)[0-9a-f]*$" | \
    tr -d '=\r\n\t' | xxd -r -p > $OUTPUT_DIR/session_udp_$i.bin
done

echo
echo "$OUTPUT_DIR/"
ls -l $OUTPUT_DIR/
