#!/usr/bin/perl
#
# report_inet_info.pl - updated 2018-12-03 - v1.1.0
#
# Generates list of devices, interfaces, addresses, and subnets based on configuration files.
# 
# - grabs interface description and route names
# - grabs and displays asa security zone info
# - detects and notes shutdown interfaces
# - added the ability to change sort order
# - added the ability to filter based on regex
# - added the ability specify which columns to display on output

use Getopt::Long;
use Data::Dumper;
use Storable;

$debug = "";
GetOptions ("debug"  => \$debug,
            "connected" => \$connected,
            "sort=s"   => \$sort_order,
            "filter=s" => \$filter,
            "columns=s" => \$column_list );

%variables = ();

@column_index = ("index", "hostname", "device_type", "interface", "address", "subnet", "description", "connected");
%columns = ("index"       => {'enabled' => 0, 'display' => 'Index'},
            "hostname"    => {'enabled' => 0, 'display' => 'Hostname'},
            "device_type" => {'enabled' => 0, 'display' => 'Device Type'},
            "interface"   => {'enabled' => 0, 'display' => 'Interface'},
            "address"     => {'enabled' => 0, 'display' => 'IP Address'},
            "subnet"      => {'enabled' => 0, 'display' => 'Subnet'},
            "description" => {'enabled' => 0, 'display' => 'Description'},
            "connected"   => {'enabled' => 0, 'display' => 'Connected'});

if($column_list)
{
  foreach(split(",", $column_list))
  {
    $columns{$_}->{'enabled'} = 1;
  }
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
  print "  --sort=<type>      Sort on (host, subnet (default))\n";
  print "  --filter=<regex>   Filter results based on regex\n";
  print "  --columns=<list>   Comma Separated list of columns to display.\n";
  print "                     index,hostname,device_type,interface,address,subnet,description,connected\n";
  print "\n";
  exit;
}


%networks = ();
$hash_index = 0;
@interface_keys = ();

# print header
$spacer = "";
foreach(@column_index)
{
  if($columns{$_}->{'enabled'})
  {
    print $spacer . $columns{$_}->{'display'};
    $spacer = ", ";
  }
}
print "\n";

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
        $description =~ s/\"/\\\"/;
        
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
if($sort_order eq "host")
{
  foreach $key (sort { $networks{$a}->{hostname} cmp $networks{$b}->{hostname}
                     or $networks{$a}->{interface} cmp $networks{$b}->{interface}
                     or $networks{$a}->{dec_subnet} <=> $networks{$b}->{dec_subnet}
                     or $networks{$a}->{mask} <=> $networks{$b}->{mask}
                     or $networks{$a}->{dec_address} <=> $networks{$b}->{dec_address} } keys %networks)
  {
    printoutput($key);
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
    printoutput($key);
  }
}

sub printoutput
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
