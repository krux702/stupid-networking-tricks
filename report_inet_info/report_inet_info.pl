#!/usr/bin/perl
#
# report_inet_info.pl - updated 2018-12-24 - v1.3.0
#
# Generates list of devices, interfaces, addresses, and subnets based on configuration files.
# 
# - grabs interface description and route names
# - grabs and displays asa security zone info
# - detects and notes shutdown interfaces
# - added the ability to change sort order
# - added the ability to filter based on regex
# - added the ability specify which columns to display on output

# need to handle secondary addresses

use Getopt::Long;
use Data::Dumper;
use Storable;

$debug = "";
GetOptions ("debug"     => \$debug,
            "connected" => \$connected,
            "sort=s"    => \$sort_order,
            "filter=s"  => \$filter,
            "columns=s" => \$column_list,
            "arp"       => \$collect_arp,
            "mac"       => \$collect_mac,
            "cdp"       => \$collect_cdp,
            "source=s"  => \$source_net,
            "dest=s"    => \$dest_net );

%variables = ();

@column_index = ("index", "hostname", "device_type", "interface", "address", "mac", "subnet", "description", "connected");
%columns = (
             "index"       => {'enabled' => 0, 'display' => 'Index'},
             "hostname"    => {'enabled' => 0, 'display' => 'Hostname'},
             "device_type" => {'enabled' => 0, 'display' => 'Device Type'},
             "interface"   => {'enabled' => 0, 'display' => 'Interface'},
             "address"     => {'enabled' => 0, 'display' => 'IP Address'},
             "mac"         => {'enabled' => 0, 'display' => 'Mac Address'},
             "subnet"      => {'enabled' => 0, 'display' => 'Subnet'},
             "description" => {'enabled' => 0, 'display' => 'Description'},
             "connected"   => {'enabled' => 0, 'display' => 'Connected'},
           );

@arp_column_index = ("hostname", "address", "mac", "interface");
%arp_columns = (
                 "hostname"  => {'enabled' => 0, 'display' => 'Hostname'},
                 "address"   => {'enabled' => 0, 'display' => 'IP Address'},
                 "mac"       => {'enabled' => 0, 'display' => 'Mac Address'},
                 "interface"   => {'enabled' => 0, 'display' => 'Interface'},
               );

@mac_column_index = ("hostname", "vlan", "mac", "type", "interface");
%mac_columns = (
                 "hostname"    => {'enabled' => 0, 'display' => 'Hostname'},
                 "vlan"        => {'enabled' => 0, 'display' => 'Vlan'},
                 "mac"         => {'enabled' => 0, 'display' => 'Mac Address'},
                 "type"        => {'enabled' => 0, 'display' => 'Type'},
                 "interface"   => {'enabled' => 0, 'display' => 'Interface'},
               );

@cdp_column_index = ("hostname", "interface", "remotehost", "remotedevice", "remoteinterface", "remoteaddress", "remoteversion");
%cdp_columns = (
                 "hostname"        => {'enabled' => 0, 'display' => 'Hostname'},
                 "interface"       => {'enabled' => 0, 'display' => 'Interface'},
                 "remotehost"      => {'enabled' => 0, 'display' => 'Remote Hostname'},
                 "remotedevice"    => {'enabled' => 0, 'display' => 'Remote Device Type'},
                 "remoteinterface" => {'enabled' => 0, 'display' => 'Remote Interface'},
                 "remoteaddress"   => {'enabled' => 0, 'display' => 'Remote Address'},
                 "remoteversion"   => {'enabled' => 0, 'display' => 'Remote Version'},
               );

if($source_net && $dest_net)
{
  # need to process connected
  $connected = 1;
}

# router#show arp
# Protocol  Address          Age (min)  Hardware Addr   Type   Interface
# Internet  1.2.3.4               222   0021.dead.beef  ARPA   Vlan10
# Internet  10.20.30.40             -   64d9.cafe.c0de  ARPA   Vlan20

if($collect_arp)
{
  # mac and arp reports are separate
  $connected = 0;

}


# switch#show mac address-table
# Vlan    Mac Address       Type        Ports
# ----    -----------       --------    -----
#  All    0100.0ccc.cccc    STATIC      CPU
#  172    0021.dead.beef    DYNAMIC     Gi0/1
# 2162    64d9.cafe.c0de    STATIC      Fa0/10 

if($collect_mac)
{
  # mac and arp reports are separate
  $connected = 0;

}

# enable output display of columns
if($column_list)
{
  foreach(split(",", $column_list))
  {
    if(defined($columns{$_}))
    {
      $columns{$_}->{'enabled'} = 1;
    }
    if(defined($mac_columns{$_}))
    {
      $mac_columns{$_}->{'enabled'} = 1;
    }
    if(defined($arp_columns{$_}))
    {
      $arp_columns{$_}->{'enabled'} = 1;
    }
    if(defined($cdp_columns{$_}))
    {
      $cdp_columns{$_}->{'enabled'} = 1;
    }
  }
}
else
{
  if($collect_arp)
  {
    $arp_columns{'hostname'}->{'enabled'} = 1;
    $arp_columns{'address'}->{'enabled'} = 1;
    $arp_columns{'mac'}->{'enabled'} = 1;
    $arp_columns{'interface'}->{'enabled'} = 1;
  }
  elsif($collect_mac)
  {
    $mac_columns{'hostname'}->{'enabled'} = 1;
    $mac_columns{'vlan'}->{'enabled'} = 1;
    $mac_columns{'mac'}->{'enabled'} = 1;
    $mac_columns{'type'}->{'enabled'} = 1;
    $mac_columns{'interface'}->{'enabled'} = 1;
  }
  elsif($collect_cdp)
  {
    $cdp_columns{'hostname'}->{'enabled'} = 1;
    $cdp_columns{'interface'}->{'enabled'} = 1;
    $cdp_columns{'remotehost'}->{'enabled'} = 1;
    $cdp_columns{'remotedevice'}->{'enabled'} = 1;
    $cdp_columns{'remoteinterface'}->{'enabled'} = 1;
    $cdp_columns{'remoteaddress'}->{'enabled'} = 1;
    $cdp_columns{'remoteversion'}->{'enabled'} = 1;
  }
  else
  {
    if($connected)
    {
      $columns{'index'}->{'enabled'} = 1;
      $columns{'connected'}->{'enabled'} = 1;
    }
    $columns{'hostname'}->{'enabled'} = 1;
    $columns{'device_type'}->{'enabled'} = 1;
    $columns{'interface'}->{'enabled'} = 1;
    $columns{'address'}->{'enabled'} = 1;
    $columns{'subnet'}->{'enabled'} = 1;
    $columns{'description'}->{'enabled'} = 1;
  }
}


# hostname  interface  subnet/mask

if($debug)
{
  print "Init:\n";
  print Data::Dumper->Dump( [ \@files ], [ qw(*files) ] );
  print Data::Dumper->Dump( [ \%variables ], [ qw(*variables) ] );
  print "\n";
}

if($#ARGV eq -1)
{
  print "Generates list of devices, interfaces, addresses, and subnets based on configuration files.\n\n";

  print "Syntax:\n\n";
  print "./report_inet_info.pl <options> <file_list>\n\n";
  print "Options:\n\n";
  print "  --debug            Enable Debugging output\n";
  print "  --connected        Process connected interfaces\n";
  print "  --mac              MAC Address table\n";
  print "  --arp              ARP Address table\n";
  print "  --sort=<type>      Sort on (host, mac, subnet (default))\n";
  print "  --filter=<regex>   Filter results based on regex\n";
  print "  --columns=<list>   Comma Separated list of columns to display.\n";
  print "                     index,hostname,device_type,interface,address,subnet,description,connected\n";
  print "\n";
  exit;
}


print_header();


@interface_keys = ();

$hash_index = 0;
%networks = ();

$arp_hash_index = 0;
%arp_table = ();

$mac_hash_index = 0;
%mac_table = ();

$cdp_hash_index = 0;
%cdp_table = ();

# process each file in @ARGV
foreach $device_file (@ARGV)
{
  $hostname = "";
  $device_type = "";
  $interface = "";
  $subnet = "";
  $address = "";
  $mask = "";
  $cidr_mask = "";
  $description = "";

  if( -r $device_file )
  {
    if($debug)
    {
      print "Reading config from: $device_file\n";
    }

    # determine device type
    open(INFILE, "<", $device_file) or die ("Unable to open file $device_file\n");
    while(<INFILE>)
    {
      # switch
      if( $_ =~ /switchport/ && $device_type eq "" )
      {
        $device_type = "switch";
      }

      # match on switches which are doing routing
      if( $_ =~ /^ip route/ && $device_type eq "switch" )
      {
        $device_type = "l3_switch";
      }
      if( $_ =~ /^router/ && $device_type eq "switch" )
      {
        $device_type = "l3_switch";
      }

      # switch which is not routing
      if( $_ =~ /^ip default-gateway/ )
      {
        $device_type = "l2_switch";
      }

      # switch which is routing
      if( $_ =~ /^ip routing/ )
      {
        $device_type = "l3_switch";
      }

      # routers usually have a license pid
      if( $_ =~ /license udi pid/ )
      {
        $device_type = "router";
      }

      # match router based on boot variable
      if( $_ =~ /boot system .*(asr|cgr|isr|c28|c29|c38|c39)/ )
      {
        $device_type = "router";
      }

      # match router based on boot variable
      if( $_ =~ /boot system .*(vg[0-9])/ )
      {
        $device_type = "voice_gateway";
      }
    }
    close(INFILE);

    # grab network numbers
    open(INFILE, "<", $device_file) or die ("Unable to open file $device_file\n");
    while(<INFILE>)
    {
      # match on show command for hostname
      if( $_ =~ /^([^#]+)#(\s+|)show/ )
      {
        $hostname = $1;
        $hostname =~ s/\s+$//;
        $hostname =~ s/\/.*$//;
      }
 
      # match on hostname <name>
      if( $_ =~ /^hostname ([^\ ]*)$/ )
      {
        $hostname = $1;
        $hostname =~ s/\s+$//;
      }

      # match on switchname <name>
      if( $_ =~ /^switchname ([^\ ]*)$/ )
      {
        $hostname = $1;
        $hostname =~ s/\s+$//;
      }

      # match on interface <interface_name>
      if( $_ =~ /^interface (.*)$/ )
      {
        $interface = $1;
        $interface =~ s/\s+$//;
      }

      # match on asa zones
      if( $_ =~ /^ nameif ([^\ ]*)$/ )
      {
        $zone = $1;
        $zone =~ s/\s+$//;
        $interface .= " ($zone)";
        $device_type = "firewall";
      }

      # asa devices have description in objects which we are not interested in here
      if( $_ =~ /^object/ )
      {
        $description = "";
      }

      # match on description
      if( $_ =~ /^ description (.*)$/ )
      {
        $description = $1;

        # remove leading/trailing whitespace, quotes, etc..
        $description =~ s/[[:punct:]\s]+$//;
        $description =~ s/^[[:punct:]\s]+//;
        # backtick quotes
        $description =~ s/\"/\\\"/g;
        
        $description = "\"$description\"";
      }

      # match on ip address <ip> <mask>
      if( $_ =~ /^\s+ip address ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/ )
      {
        $address = $1;
        $ipnum = ip2dec($address);
        $mask = $2;
        $cidr_mask = cidr_mask($mask);
        $subnet = dec2ip($ipnum, $cidr_mask);       
      }

      # match on ip address <ip>/<mask>
      if( $_ =~ /^\s+ip address ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\/([0-9]+)/ )
      {
        $address = $1;
        $ipnum = ip2dec($address);
        $cidr_mask = $2;
        $cidr_mask =~ s/\s+$//;
        $subnet = dec2ip($ipnum, $cidr_mask);       
      }

      # match route name for description
      if( $_ =~ /ip route .* name ([^\ ]+)/ )
      {
        $description = $1;
        $description =~ s/[[:punct:]\s]+$//;
        $description =~ s/^[[:punct:]\s]+//;
      }

      # match ip route <ip> <mask> <gateway>
      if( $_ =~ /ip route ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/ )
      {
        $subnet = $1;
        $mask = $2;
        $cidr_mask = cidr_mask($mask);
        $address = $3;
        $ipnum = ip2dec($address);

        @interface_keys = find_route_keys($ipnum, $hostname);

        if($#interface_keys != -1)
        {
          $interface = "Route -> " . $networks{$interface_keys[0]}{interface};
        }
        else
        {
          $interface = "Route";
        }
      }

      # grab routes from ASA firewall
      if( $_ =~ /route ([^\ ]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/ )
      {
        $subnet = $2;
        $mask = $3;
        $cidr_mask = cidr_mask($mask);
        $address = $4;
        $ipnum = ip2dec($address);

        @interface_keys = find_route_keys($ipnum, $hostname);
        if($#interface_keys != -1)
        {
          $interface = "Route -> " . $networks{$interface_keys[0]}{interface};
        }
        else
        {
          $interface = "Route -> $1";
        }
      }

      # if we found the cidr mask, assume we found everything else and add to database
      if($cidr_mask)
      {
        $hash_index++;
        $networks{$hash_index} = { 'hostname' => "$hostname",
                                   'device_type' => "$device_type",
                                   'interface' => "$interface",
                                   'address' => "$address",
                                   'dec_address' => ip2dec("$address"),
                                   'subnet' => "$subnet",
                                   'dec_subnet' => ip2dec("$subnet"),
                                   'mask' => "$cidr_mask",
                                   'description' => "$description" };

        if($debug)
        {
          print "$hostname, $device_type, $interface, $address, $subnet/$cidr_mask\n";
        }

        # $interface = "";
        # $address = "";
        $subnet = "";
        $mask = "";
        $cidr_mask = "";
        $description = "";
      }

      # match on shutdown, which we have to process after the fact
      if( $address && $interface && $_ =~ /^ shutdown/ )
      {
        $interface .= " shutdown";
        $networks{$hash_index}->{interface} = $interface;
        $interface = "";
      }

      # no longer in interface so blank out interface / description
      if( $_ =~ /^!/ )
      {
        $address = "";
        $interface = "";
        $description = "";
      }

      # process show interface, which should happen after show run in your output
      # show interface
      # FastEthernet0/1 is up, line protocol is up (connected)
      # show ip interface
      # Vlan1 is administratively down, line protocol is down
      # Vlan21 is up, line protocol is up
      # FastEthernet0/1 is up, line protocol is up
      if( $_ =~ /(.*) is ([^,]+), line protocol is (.*)/ )
      {
        $interface = $1;
        # Interface GigabitEthernet0/0 "outside", is up, line protocol is up
        $interface =~ s/Interface ([^\s]+) "([^"]+)"/\1 (\2)/;
        $interface =~ s/\s+$//;
        $interface_status = "$2, line protocol is $3";
        $interface_status =~ s/, [Aa]utostate enabled//;
        $interface_status =~ s/\s+$//;
        $interface_status = "\"$interface_status\"";
      }

      #  Hardware is Fast Ethernet, address is 5835.dead.beef (bia 5835.dead.beef)
      if( $_ =~ /(address is|MAC address|address:) ([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})/ )
      {
        $interface_mac = $2;
        @interface_keys = find_interface($interface, $hostname);

        if(! ($interface_mac =~ /^(3333\.0000\.|0000\.0000\.|ffff\.ffff\.)/) )
        {
          foreach $key (@interface_keys)
          {
            # add mac to interface
            $networks{$key}{mac} = $interface_mac;
          }

          # add local interface to mac table
          $mac_hash_index++;
          $mac_table{$mac_hash_index}{hostname} = $hostname;
          $mac_table{$mac_hash_index}{interface} = $interface;
          $mac_table{$mac_hash_index}{mac} = $interface_mac;
          $mac_table{$mac_hash_index}{type} = "interface";
        }
      }


      #  * - primary entry, G - Gateway MAC, (R) - Routed MAC, O - Overlay MAC
      #  age - seconds since last seen,+ - primary entry using vPC Peer-Link,
      #  (T) - True, (F) - False, C - ControlPlane MAC
      #    VLAN     MAC Address      Type      age     Secure NTFY Ports
      # ---------+-----------------+--------+---------+------+----+------------------
      # *    1     000d.5555.4333   dynamic  0         F      F    Po8
      # +    1     000d.5555.4444   dynamic  0         F      F    Po8
      # G 1023     843d.dead.beef   static   -         F      F    sup-eth1(R)
      # G 1024     843d.dead.b33f   static   -         F      F    vPC Peer-Link(R)
      if( $_ =~ /([0-9]+|All)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(static|dynamic)\s+([0-9]+|-)\s+([^\s]+)\s+([^\s]+)\s+(.*)/i )
      {
        $vlan = $1;
        $interface_mac = $2;
        $type = $3;
        $interface = $7;
        $interface =~ s/\s+$//;
        if($type ne "CPU" && ! ($interface_mac =~ /^(3333\.0000\.|0000\.0000\.|ffff\.ffff\.)/) )
        {
          $mac_hash_index++;
          $mac_table{$mac_hash_index}{hostname} = $hostname;
          $mac_table{$mac_hash_index}{interface} = $interface;
          $mac_table{$mac_hash_index}{vlan} = $vlan;
          $mac_table{$mac_hash_index}{mac} = $interface_mac;
          $mac_table{$mac_hash_index}{type} = $type;
        }
      }

      #   vlan   mac address     type    learn     age              ports
      # ------+----------------+--------+-----+----------+--------------------------
      # *  817  0100.5555.1111   static  Yes          -   
      # *  817  5ce0.dead.beef   dynamic  Yes          5   Po16
      # * 3005  9c4e.dead.b33f   dynamic  Yes        120   Gi1/47
      elsif( $_ =~ /([0-9]+|All)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(static|dynamic)\s+([^\s]+)\s+([^\s]+)\s+(.*)/i )
      {
        $vlan = $1;
        $interface_mac = $2;
        $type = $3;
        $interface = $6;
        $interface =~ s/\s+$//;
        if($type ne "CPU" && ! ($interface_mac =~ /^(3333\.0000\.|0000\.0000\.|ffff\.ffff\.)/) )
        {
          $mac_hash_index++;
          $mac_table{$mac_hash_index}{hostname} = $hostname;
          $mac_table{$mac_hash_index}{interface} = $interface;
          $mac_table{$mac_hash_index}{vlan} = $vlan;
          $mac_table{$mac_hash_index}{mac} = $interface_mac;
          $mac_table{$mac_hash_index}{type} = $type;
        }
      }
      #  vlan   mac address     type        protocols               port
      # -------+---------------+--------+---------------------+--------------------
      #  202    0004.aaaa.2222    static ip,ipx,assigned,other GigabitEthernet6/46
      #  202    0004.bbbb.3333    static ip,ipx,assigned,other GigabitEthernet6/48
      #  202    0007.cccc.4444    static ip,ipx,assigned,other GigabitEthernet5/35
      elsif( $_ =~ /([0-9]+|All)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(static|dynamic)\s+([^\s]+)\s+(.*)/i )
      {
        $vlan = $1;
        $interface_mac = $2;
        $type = $3;
        $interface = $5;
        $interface =~ s/\s+$//;
        if($type ne "CPU" && ! ($interface_mac =~ /^(3333\.0000\.|0000\.0000\.|ffff\.ffff\.)/) )
        {
          $mac_hash_index++;
          $mac_table{$mac_hash_index}{hostname} = $hostname;
          $mac_table{$mac_hash_index}{interface} = $interface;
          $mac_table{$mac_hash_index}{vlan} = $vlan;
          $mac_table{$mac_hash_index}{mac} = $interface_mac;
          $mac_table{$mac_hash_index}{type} = $type;
        }
      }
      # Vlan    Mac Address       Type        Ports
      # ----    -----------       --------    -----
      #  All    0100.aaaa.cccc    STATIC      CPU
      #  172    0021.bbbb.cccc    DYNAMIC     Gi0/1
      # 2162    64d9.cccc.dddd    STATIC      Fa0/10 
      elsif( $_ =~ /([0-9]+|All)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(static|dynamic)\s+([A-Z][^\s]+)/i )
      {
        $vlan = $1;
        $interface_mac = $2;
        $type = $3;
        $interface = $4;
        $interface =~ s/\s+$//;
        if($type ne "CPU" && !($interface_mac =~ /^(3333\.0000\.|0000\.0000\.|ffff\.ffff\.)/))
        {
          $mac_hash_index++;
          $mac_table{$mac_hash_index}{hostname} = $hostname;
          $mac_table{$mac_hash_index}{interface} = $interface;
          $mac_table{$mac_hash_index}{vlan} = $vlan;
          $mac_table{$mac_hash_index}{mac} = $interface_mac;
          $mac_table{$mac_hash_index}{type} = $type;
        }
      }

      # Protocol  Address          Age (min)  Hardware Addr   Type   Interface
      # Internet  10.20.30.1              -   f8b7.aaaa.bbbb  ARPA   GigabitEthernet0/0/0.20
      # Internet  10.20.30.2             67   e8ba.aaaa.cccc  ARPA   GigabitEthernet0/0/0.20
      # Internet  10.20.30.3             72   e8ba.aaaa.5555  ARPA   GigabitEthernet0/0/0.20

      if( $_ =~ /^(Internet)\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([0-9]+|-)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+([^\s]+)\s+(.*)/i )
      {
        $address = $2;
        $interface_mac = $4;
        $interface = $6;
        $interface =~ s/\s+$//;

        $arp_hash_index++;
        $arp_table{$arp_hash_index}{hostname} = $hostname;
        $arp_table{$arp_hash_index}{address} = $address;
        $arp_table{$arp_hash_index}{dec_address} = ip2dec("$address");
        $arp_table{$arp_hash_index}{interface} = $interface;
        $arp_table{$arp_hash_index}{mac} = $interface_mac;
      }

      # 10.10.20.20     00:06:29  a0e0.dddd.eeee  Vlan19          
      # 10.20.20.1      00:07:41  843d.cccc.bbbb  Ethernet5/48    

      elsif( $_ =~ /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([^\s]+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+([^\s]+)/i )
      {
        $address = $1;
        $interface_mac = $3;
        $interface = $4;
        $interface =~ s/\s+$//;

        $arp_hash_index++;
        $arp_table{$arp_hash_index}{hostname} = $hostname;
        $arp_table{$arp_hash_index}{address} = $address;
        $arp_table{$arp_hash_index}{dec_address} = ip2dec("$address");
        $arp_table{$arp_hash_index}{interface} = $interface;
        $arp_table{$arp_hash_index}{mac} = $interface_mac;
      }

      # outside 172.31.254.1 7c67.7777.8888 453
      # inside 10.100.90.9 0025.bbbb.dddd 7055

      elsif( $_ =~ /^\s+([^\s]+)\s+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+(.*)/i )
      {
        $address = $2;
        $interface_mac = $3;
        $interface = $1;
        $interface =~ s/\s+$//;

        $arp_hash_index++;
        $arp_table{$arp_hash_index}{hostname} = $hostname;
        $arp_table{$arp_hash_index}{address} = $address;
        $arp_table{$arp_hash_index}{dec_address} = ip2dec("$address");
        $arp_table{$arp_hash_index}{interface} = $interface;
        $arp_table{$arp_hash_index}{mac} = $interface_mac;
      }

       # cdp neighbor detail
      if( $_ =~ /^(Device ID|System Name):(.*)/ )
      {
        $in_cdp = 1;
        $cdp_remotehost = $2;
        $cdp_remotehost =~ s/^\s+//;
        $cdp_remotehost =~ s/\s+$//;
      }
      if( $in_cdp && $_ =~ /^\s+(IPv4 Address|IP address): ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/ )
      {
        $cdp_remoteaddress = $2;
        $cdp_remotedecaddress = ip2dec("$cdp_remoteaddress");;
      }
      if( $in_cdp && $_ =~ /^Platform: ([^,]+)/ )
      {
        $cdp_remotedevice = $1;
        $cdp_remotedevice =~ s/^\s+//;
        $cdp_remotedevice =~ s/\s+$//;
      }
      if( $in_cdp && $_ =~ /^Interface: ([^,]+), .*\): (.*)/ )
      {
        $cdp_interface = $1;
        $cdp_remoteinterface = $2;
        $cdp_remoteinterface =~ s/\s+$//;
      }

      # grab cdp version info
      if( $in_cdp eq 2 )
      {
        $in_cdp = 1;
        $cdp_remoteversion = $_;
        $cdp_remoteversion =~ s/^\s+//;
        $cdp_remoteversion =~ s/\s+$//;
        $cdp_remoteversion =~ s/\"/\\\"/;
        $cdp_remoteversion = "\"$cdp_remoteversion\"";
      }
      if( $in_cdp && $_ =~ /^Version/ )
      {
        $in_cdp = 2;
      }

      # collected all cdp info
      if($in_cdp && $cdp_remoteaddress && $cdp_remoteinterface && $cdp_remotehost && $cdp_remotedevice && $cdp_remoteversion)
      {
        $cdp_hash_index++;
        $cdp_table{$cdp_hash_index}{hostname} = $hostname;
        $cdp_table{$cdp_hash_index}{interface} = $cdp_interface;
        $cdp_table{$cdp_hash_index}{remotehost} = $cdp_remotehost;
        $cdp_table{$cdp_hash_index}{remoteinterface} = $cdp_remoteinterface;
        $cdp_table{$cdp_hash_index}{remotedevice} = $cdp_remotedevice;
        $cdp_table{$cdp_hash_index}{remoteaddress} = $cdp_remoteaddress;
        $cdp_table{$cdp_hash_index}{remotedecaddress} = $cdp_remotedecaddress;
        $cdp_table{$cdp_hash_index}{remoteversion} = $cdp_remoteversion;

        $in_cdp = 0;
        $cdp_interface = "";
        $cdp_remotehost = "";
        $cdp_remoteinterface = "";
        $cdp_remotedevice = "";
        $cdp_remoteaddress = "";
        $cdp_remotedecaddress = "";
        $cdp_remoteversion = "";
      }

    }
    close(INFILE);
  }
  else
  {
    print "Unable to open file: $device_file\n";
  }
}

if($debug)
{
  print "\n\n--- sorted results follow ---\n\n";
}

@interface_keys = ();

if($connected)
{
  # build list of connections
  foreach $key (keys %networks)
  {
    if( ! ( $networks{$key}{interface} =~ /Route/ )
        && ! (  $networks{$key}{interface} =~ /(loopback|management|shutdown)/i ) )
    {
      @{ $networks{$key}->{connected} } = ();
      @interface_keys = find_route_keys($networks{$key}->{dec_address}, "");
      foreach $interface (@interface_keys)
      {
        # $interface != $key
        if($networks{$interface}{hostname} ne $networks{$key}{hostname} 
           && ! (  $networks{$interface}{interface} =~ /(loopback|management|shutdown)/i ) )
        {
          push @{ $networks{$key}->{connected} }, $interface
        }
      }
    }
  }
}

# sort the hash of hashes
if($collect_arp)
{
  if($sort_order eq "mac")
  {
    foreach $key (sort { $arp_table{$a}->{mac} cmp $arp_table{$b}->{mac}
                       or $arp_table{$a}->{hostname} cmp $arp_table{$b}->{hostname}
                       or $arp_table{$a}->{interface} cmp $arp_table{$b}->{interface}
                       or $arp_table{$a}->{dec_address} <=> $arp_table{$b}->{dec_address} } keys %arp_table)
    {
      print_arp_output($key);
    }
  }
  else
  {
    foreach $key (sort { $arp_table{$a}->{hostname} cmp $arp_table{$b}->{hostname}
                       or $arp_table{$a}->{interface} cmp $arp_table{$b}->{interface}
                       or $arp_table{$a}->{dec_address} <=> $arp_table{$b}->{dec_address}
                       or $arp_table{$a}->{mac} cmp $arp_table{$b}-{mac} } keys %arp_table)
    {
      print_arp_output($key);
    }
  }

}
elsif($collect_mac)
{
  if($sort_order eq "mac")
  {
    foreach $key (sort { $mac_table{$a}->{mac} cmp $mac_table{$b}->{mac}
                       or $mac_table{$a}->{hostname} cmp $mac_table{$b}->{hostname}
                       or $mac_table{$a}->{interface} cmp $mac_table{$b}->{interface}
                       or $mac_table{$a}->{type} cmp $mac_table{$b}->{type} } keys %mac_table)
    {
      print_mac_output($key);
    }
  }
  else
  {
    foreach $key (sort { $mac_table{$a}->{hostname} cmp $mac_table{$b}->{hostname}
                       or $mac_table{$a}->{interface} cmp $mac_table{$b}->{interface}
                       or $mac_table{$a}->{type} cmp $mac_table{$b}->{type}
                       or $mac_table{$a}->{mac} cmp $mac_table{$b}->{mac} } keys %mac_table)
    {
      print_mac_output($key);
    }
  }
}
elsif($collect_cdp)
{
  if($sort_order eq "remotehost")
  {
    foreach $key (sort { $cdp_table{$a}->{remotehostname} cmp $cdp_table{$b}->{remotehostname}
                       or $cdp_table{$a}->{remoteinterface} cmp $cdp_table{$b}->{remoteinterface}
                       or $cdp_table{$a}->{hostname} cmp $cdp_table{$b}->{hostname}
                       or $cdp_table{$a}->{interface} cmp $cdp_table{$b}->{interface} } keys %cdp_table)
    {
      print_cdp_output($key);
    }
  }
  else
  {
    foreach $key (sort { $cdp_table{$a}->{hostname} cmp $cdp_table{$b}->{hostname}
                       or $cdp_table{$a}->{interface} cmp $cdp_table{$b}->{interface} } keys %cdp_table)
    {
      print_cdp_output($key);
    }
  }
}
else
{
  if($sort_order eq "host")
  {
    foreach $key (sort { $networks{$a}->{hostname} cmp $networks{$b}->{hostname}
                       or $networks{$a}->{interface} cmp $networks{$b}->{interface}
                       or $networks{$a}->{dec_subnet} <=> $networks{$b}->{dec_subnet}
                       or $networks{$a}->{mask} <=> $networks{$b}->{mask}
                       or $networks{$a}->{dec_address} <=> $networks{$b}->{dec_address} } keys %networks)
    {
      print_output($key);
    }
  }
  else
  {
    foreach $key (sort { $networks{$a}->{dec_subnet} <=> $networks{$b}->{dec_subnet}
                       or $networks{$a}->{mask} <=> $networks{$b}->{mask}
                       or $networks{$a}->{dec_address} <=> $networks{$b}->{dec_address}
                       or $networks{$a}->{interface} cmp $networks{$b}->{interface}
                       or $networks{$a}->{hostname} cmp $networks{$b}->{hostname} } keys %networks)
    {
      print_output($key);
    }
  }
}


sub print_header
{
  # print header
  $spacer = "";
  if($collect_arp)
  {
    foreach(@arp_column_index)
    {
      if($arp_columns{$_}->{'enabled'})
      {
        print $spacer . $arp_columns{$_}->{'display'};
        $spacer = ", ";
      }
    }
  }
  elsif($collect_mac)
  {
    foreach(@mac_column_index)
    {
      if($mac_columns{$_}->{'enabled'})
      {
        print $spacer . $mac_columns{$_}->{'display'};
        $spacer = ", ";
      }
    }
  }
  elsif($collect_cdp)
  {
    foreach(@cdp_column_index)
    {
      if($cdp_columns{$_}->{'enabled'})
      {
        print $spacer . $cdp_columns{$_}->{'display'};
        $spacer = ", ";
      }
    }
  }
  else
  {
    foreach(@column_index)
    {
      if($columns{$_}->{'enabled'})
      {
        print $spacer . $columns{$_}->{'display'};
        $spacer = ", ";
      }
    }
  }
  print "\n";
}


sub print_output
{
  my ($key) = @_;

  my $output = "";
  my $spacer = "";
  foreach(@column_index)
  {
    if($columns{$_}->{'enabled'})
    {
      $output .= $spacer;
      if($_ eq 'index')
      {
        $output .= "$key";
      }
      elsif($_ eq 'subnet')
      {
        $output .= $networks{$key}{subnet} . "/" . $networks{$key}{mask};
      }
      elsif($_ eq 'connected')
      {
        $connected_work = "";
        foreach $interface (@{ $networks{$key}->{connected} })
        {
          if($connected_work)
          {
            $connected_work .= ", ";
          }
          $connected_work .= "$interface";
        }
        $output .= "\"" . $connected_work . "\"";
      }
      else
      {
        $output .= $networks{$key}{$_};
      }
      $spacer = ", ";
    }
  }
  $output .= "\n";

  if($filter)
  {
    # filter based on regex
    if($output =~ /$filter/i )
    {
      print $output;
    }
  }
  else
  {
    print $output;
  }
}

sub print_mac_output
{
  my ($key) = @_;

  my $output = "";
  my $spacer = "";
  foreach(@mac_column_index)
  {
    if($mac_columns{$_}->{'enabled'})
    {
      $output .= $spacer;
      if($_ eq 'index')
      {
        $output .= "$key";
      }
      else
      {
        $output .= $mac_table{$key}{$_};
      }
      $spacer = ", ";
    }
  }
  $output .= "\n";

  if($filter)
  {
    # filter based on regex
    if($output =~ /$filter/i )
    {
      print $output;
    }
  }
  else
  {
    print $output;
  }
}

sub print_arp_output
{
  my ($key) = @_;

  my $output = "";
  my $spacer = "";
  foreach(@arp_column_index)
  {
    if($arp_columns{$_}->{'enabled'})
    {
      $output .= $spacer;
      if($_ eq 'index')
      {
        $output .= "$key";
      }
      else
      {
        $output .= $arp_table{$key}{$_};
      }
      $spacer = ", ";
    }
  }
  $output .= "\n";

  if($filter)
  {
    # filter based on regex
    if($output =~ /$filter/i )
    {
      print $output;
    }
  }
  else
  {
    print $output;
  }
}

sub print_cdp_output
{
  my ($key) = @_;

  my $output = "";
  my $spacer = "";
  foreach(@cdp_column_index)
  {
    if($cdp_columns{$_}->{'enabled'})
    {
      $output .= $spacer;
      if($_ eq 'index')
      {
        $output .= "$key";
      }
      else
      {
        $output .= $cdp_table{$key}{$_};
      }
      $spacer = ", ";
    }
  }
  $output .= "\n";

  if($filter)
  {
    # filter based on regex
    if($output =~ /$filter/i )
    {
      print $output;
    }
  }
  else
  {
    print $output;
  }
}

sub ip2dec
{
  my ($ip) = @_;

  $ipnum = 0;
  if($ip =~ /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/ )
  {
    $ipnum = ($1 * 256 ** 3) + ($2 * 256 ** 2) + ($3 * 256) + $4;
  }
  return $ipnum;
}

sub dec2ip
{
  my ($ipnum, $mask) = @_;

  my $smask = ((256 ** 4) - 1 ) ^ (2 ** (32 - $mask) - 1);
  my $snum = $ipnum & $smask;

  my $octa = $snum % (256);
  $snum = $snum - $octa;
  my $octb = ($snum % (256 ** 2)/256);

  $snum = $snum - $octb * 256;
  my $octc = ($snum % (256 ** 3)/(256 ** 2));

  $snum = $snum - $octc * (256 ** 2);
  my $octd = ($snum % (256 ** 4)/(256 ** 3));
  my $ip = "$octd.$octc.$octb.$octa";

  return $ip;
}

sub cidr_mask
{
  my ($mask) = @_;

  my @maskbin = split("[.]", $mask);
  my ( $maskdec ) = unpack ( "N", pack( "C4", @maskbin ) );
  my $maskbin = sprintf ("%b",$maskdec);
  $maskbin =~ s/0+$//;
  my $cidr_mask = length($maskbin);

  return $cidr_mask;
}

sub find_route_keys
{
  my ($gateway, $host) = @_;

  my @key_list = ();

  # parse through our database of subnets
  foreach $key (keys %networks)
  {
    # match on the host
    if( ( $networks{$key}{hostname} eq $host || $host eq "" )
        && ! ( $networks{$key}{interface} =~ /Route/ ) )
    {
      # check if the gateway IP is in the subnet we are checking
      if( $networks{$key}{subnet} eq dec2ip($gateway, $networks{$key}{mask}) )
      {
        push @key_list, $key;
      }
    }
  }

  return @key_list;
}

sub find_interface
{
  my ($interface,$host) = @_;
  # parse through our database of subnets

  my @key_list = ();

  foreach $key (keys %networks)
  {
    # match on the host
    if( ( $networks{$key}{hostname} eq $host && $host ne "" )
        && ( $networks{$key}{interface} eq $interface && $interface ne "" ) )
    {
      push @key_list, $key;
    }
  }

  return @key_list;
}
