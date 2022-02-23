#!/bin/bash

./report_inet_info.pl --columns=hostname,device_type,interface,address,subnet,description --sort=host \
 LIST_OF_FILES_TO_SCAN \
 | grep -v Route > network_export.csv

cat network_export.csv | sed -E "s/^([^,]+), ([^,]+), ([^,]+), ([^,]+), ([^,]+), (.*)/\1,\2,\1 - \3, \1, \6, \4, \5/" > network_maltego_import.csv
