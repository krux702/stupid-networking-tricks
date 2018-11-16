#!/usr/bin/perl

use Data::Dumper;
use Getopt::Long;

$debug = "";
GetOptions ("debug"  => \$debug,
            "expand" => \$expand_acls);

# item{name} = (  parents => [...],
#                children => [...] )

($filename) = @ARGV;

if(!$filename)
{
  print "Reads in the configuration of an ASA firewall, and displays the objects,
and their relationship to one another.  Indicates objects which are not referenced
by any ACLs for potiential firewall cleanup.

SYNTAX:

./parse-asa-objects <options> <config_file_name>


OPTIONS:

--expand   Expand out ACLs

";

  exit;
}

# initialize top level items
%asa_objects = ();

$asa_objects{"CRYPTO_MAPS"}{'parents'} = ["SYSTEM"];
$asa_objects{"CRYPTO_MAPS"}{'children'} = [];

$asa_objects{"ACCESS_GROUPS"}{'parents'} = ["SYSTEM"];
$asa_objects{"ACCESS_GROUPS"}{'children'} = [];

$asa_objects{"NAT_RULES"}{'parents'} = ["SYSTEM"];
$asa_objects{"NAT_RULES"}{'children'} = [];


$current_object = "";

open (FILE, "<$filename");

while(<FILE>)
{
  if($_ =~ /^object (network|service) ([a-zA-Z0-9\._-]*)/)
  {
    $current_object = "OBJECT: $2";
    $asa_objects{$current_object}{'parents'} = [];
    $asa_objects{$current_object}{'children'} = [];
  }

  if($_ =~ /^object-group (network|service) ([a-zA-Z0-9\._-]*)/)
  {
    $current_object = "OBJECT-GROUP: $2";
    $asa_objects{$current_object}{'parents'} = [];
    $asa_objects{$current_object}{'children'} = [];
  }
  if($_ =~ /^ group-object (.*)$/)
  {
     push @{ $asa_objects{"OBJECT-GROUP: $1"}{'parents'}}, $current_object;
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT-GROUP: $1";
  }
  if($_ =~ /^ network-object object (.*)$/)
  {
     push @{ $asa_objects{"OBJECT: $1"}{'parents'}}, $current_object;
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT: $1";
  }
  if($_ =~ /^ service-object object (.*)$/)
  {
     push @{ $asa_objects{"OBJECT: $1"}{'parents'}}, $current_object;
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT: $1";
  }

  if($_ =~ /^access-list (.*) extended .*/ )
  {
    $current_object = "ACL: $1";
    $asa_objects{$current_object}{'children'} = [];

    $acl = $_;
    while($acl =~ s/(object-group) ([^\ ]*)//)
    {
      push @{ $asa_objects{"OBJECT-GROUP: $2"}{'parents'} }, $current_object;
      push @{ $asa_objects{$current_object}{'children'} }, "OBJECT-GROUP: $2";
    }
    while($acl =~ s/(object) ([^\ ]*)//)
    {
      push @{ $asa_objects{"OBJECT: $2"}{'parents'} }, $current_object;
      push @{ $asa_objects{$current_object}{'children'} }, "OBJECT: $2";
    }
  }

  # match on ACL assigned to access-group
  if($_ =~ /^access-group ([^\ ]+) (in|out) interface ([^\s]+)/)
  {
    $acl = "ACL: $1";
    $access_group = "ACCESS-GROUP: $3 $2";
    push @{ $asa_objects{$acl}{'parents'} }, $access_group;
    $asa_objects{$access_group}{'parents'} = ["ACCESS_GROUPS"];
    push @{ $asa_objects{$access_group}{'children'} }, $acl;
    push @{ $asa_objects{"ACCESS_GROUPS"}{'children'} }, $access_group;
  }

  # crypto map <map_name> <number> match address <acl>

  # match on ACL assigned to crypto map
  if($_ =~ /^crypto map ([^\ ]+) .*match address ([^\s]+)/)
  {
    $crypto_map = "CRYPTO_MAP: $1";
    $acl = "ACL: $2";
    push @{ $asa_objects{$acl}{'parents'} }, $crypto_map;
    $asa_objects{$crypto_map}{'parents'} = ["CRYPTO_MAPS"];
    push @{ $asa_objects{$crypto_map}{'children'} }, $acl;
    push @{ $asa_objects{"CRYPTO_MAPS"}{'children'} }, $crypto_map;
  }

  # Try to match on nat rules, which are complex
  if($_ =~ /^( nat|nat) \(([^,]+),([^\)]+)\) (.*)/)
  {
    $nat_rule = "NAT ($2,$3):";
    $nat = " $4";
    while($nat =~ s/ ([^\s]+)//)
    {
      if( find_object($1) ne "" )
      {
        push @{ $asa_objects{$nat_rule}{'children'} }, find_object($1);
        push @{ $asa_objects{find_object($1)}{'parents'} }, $nat_rule;
        $asa_objects{$nat_rule}{'parents'} = ["NAT_RULES"];
        push @{ $asa_objects{"NAT_RULES"}{'children'} }, $nat_rule;
      }
    }
  }
}

close(FILE);

print "\n---------------\n";
print "Dump of objects\n";
print "---------------\n";

print Data::Dumper->Dump( [ \%asa_objects ], [ qw(*asa_objects) ] );


print "\n--------------------\n";
print "Unreferenced objects\n";
print "--------------------\n";

foreach $key (keys %asa_objects)
{
  $parents = $#{$asa_objects{$key}{'parents'}};
  if($parents eq -1)
  {
    print "$key\n";
  }
}

sub find_object
{
  my ($object) = @_;

  if(defined $asa_objects{"OBJECT: $object"})
  {
    return "OBJECT: $object";
  }
  if(defined $asa_objects{"OBJECT-GROUP: $object"})
  {
    return "OBJECT-GROUP: $object";
  }
}
