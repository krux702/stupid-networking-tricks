#!/usr/bin/perl

use Term::ANSIColor qw(:constants);
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
     push_uniq("OBJECT-GROUP: $1", 'parents', $current_object);
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT-GROUP: $1";
  }
  if($_ =~ /^ network-object object (.*)$/)
  {
     push_uniq("OBJECT: $1", 'parents', $current_object);
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT: $1";
  }
  elsif($_ =~ /^ network-object (.*)$/)
  {
    push @{ $asa_objects{$current_object}{'items'}}, $1;
  }

  if($_ =~ /^ (subnet|host) (.*)$/)
  {
    push @{ $asa_objects{$current_object}{'items'}}, "$1 $2";
  }

  if($_ =~ /^ service-object object (.*)$/)
  {
     push_uniq("OBJECT: $1", 'parents', $current_object);
     push @{ $asa_objects{$current_object}{'children'}}, "OBJECT: $1";
  }
  elsif($_ =~ /^ service-object (.*)$/)
  {
    push @{ $asa_objects{$current_object}{'items'}}, $1;
  }

  if($_ =~ /^ fqdn v4 (.*)$/)
  {
    push @{ $asa_objects{$current_object}{'items'}}, "fqdn v4 $1";
  }


  if($_ =~ /^access-list (.*) (standard|extended) (.*)/ )
  {
    $current_object = "ACL: $1";
    $acl = "$2 $3";
    $acl =~ s/\s+$//;

    $asa_objects{$current_object}{'children'} = [];
    push @{ $asa_objects{$current_object}{'items'} }, $acl;

    while($acl =~ s/(object-group) ([^\ ]*)//)
    {
      push_uniq("OBJECT-GROUP: $2", 'parents', $current_object);
      push @{ $asa_objects{$current_object}{'children'} }, "OBJECT-GROUP: $2";
    }
    while($acl =~ s/(object) ([^\ ]*)//)
    {
      push_uniq("OBJECT-GROUP: $2", 'parents', $current_object);
      push @{ $asa_objects{$current_object}{'children'} }, "OBJECT: $2";
    }
  }

  # match on ACL assigned to access-group
  if($_ =~ /^access-group ([^\ ]+) (in|out) interface ([^\s]+)/)
  {
    $acl = "ACL: $1";
    $access_group = "ACCESS-GROUP: $3 $2";
    push_uniq($acl, 'parents', $access_group);
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
    push_uniq($acl, 'parents', $crypto_map);
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
        push_uniq(find_object($1), 'parents', $nat_rule);
        $asa_objects{$nat_rule}{'parents'} = ["NAT_RULES"];
        push_uniq("NAT_RULES", 'children', $nat_rule);
      }
    }
  }

  # group-policy <group_policy_name> internal
  # group-policy <group_policy_name> attributes
  #  vpn-filter value <acl name>
  #
  #  vpn-group-policy <group_policy_name>
  #  default-group-policy <group_policy_name>

  # access-list <name> standard permit host <ip>


}

close(FILE);

print RED,BOLD,"\n---------------\n";
print "Dump of objects\n";
print "---------------\n",RESET;

print Data::Dumper->Dump( [ \%asa_objects ], [ qw(*asa_objects) ] );


if($expand_acls)
{
  print RED,BOLD,"\n-------------\n";
  print "Expanded ACLs\n";
  print "-------------\n",RESET;

  foreach $key (sort keys %asa_objects)
  {
    if($key =~ /^ACL: /)
    {
      print BOLD, BLUE, "$key\n", RESET;
      foreach $acl (@{$asa_objects{$key}{'items'}})
      {
        print BOLD, WHITE, "$acl\n", RESET;
        expand_acl($acl);

      }
      print "\n";
    }
  }
}


print RED,BOLD,"\n--------------------\n";
print "Unreferenced objects\n";
print "--------------------\n",RESET;

foreach $key (sort keys %asa_objects)
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

sub expand_acl
{
  my ($acl) = @_;

  @expanded_acl = ("");
  $acl_work = "";

  while($acl)
  {
    if($acl =~ s/^object ([^\s]+)//)
    {
      $object = "OBJECT: $1";

      foreach $index (keys @expanded_acl)
      {
        $expanded_acl[$index] .= $acl_work;
      }
      $acl_work = "";

      if(defined $asa_objects{$object})
      {
        @objects = expand_object($object);
        @new_expanded_acl = ();
        foreach $index (keys @expanded_acl)
        {
          foreach $item (@objects)
          {
            push @new_expanded_acl, $expanded_acl[$index] . $item;
          }
        }
        @expanded_acl = @new_expanded_acl;
      }
    }

    if($acl =~ s/^object-group ([^\s]+)//)
    {
      $object = "OBJECT-GROUP: $1";

      foreach $index (keys @expanded_acl)
      {
        $expanded_acl[$index] .= $acl_work;
      }
      $acl_work = "";

      if(defined $asa_objects{$object})
      {
        @objects = expand_object($object);
        @new_expanded_acl = ();
        foreach $index (keys @expanded_acl)
        {
          foreach $item (@objects)
          {
            push @new_expanded_acl, $expanded_acl[$index] . $item;
          }
        }
        @expanded_acl = @new_expanded_acl;
      }
    }

    if($acl =~ s/^(\s+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(extended|standard)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(permit|deny)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(ip|tcp|udp|icmp|esp|ah)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(host [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(eq [^\s]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(interface [^\s]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(any4|any6|any)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(range [0-9]+ [0-9]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(time-range [^\s]+)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(log)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^(inactive)//)
    {
      $acl_work .= $1;
    }
    elsif($acl =~ s/^([^\s]+)//)
    {
      $acl_work .= $1;
    }

  }

  foreach $index (keys @expanded_acl)
  {
    $expanded_acl[$index] .= $acl_work;
  }
  $acl_work = "";

  foreach $line (@expanded_acl)
  {
    $line =~ s/\ \ /\ /g;
    print " $line\n";
  }
  
}

sub expand_object
{
  my ($object) = @_;
  my @object_array = ();

  foreach $item (@{$asa_objects{$object}{'items'}})
  {
    push @object_array, $item;
  }
  foreach $child_object (@{$asa_objects{$object}{'children'}})
  {
    push @object_array, expand_object($child_object);
  }
  return @object_array;
}

sub push_uniq
{
  my ($object, $reference, $item) = @_;

  my $found = 0;
  foreach $test (@{$asa_objects{$object}{$reference}})
  {
    if($test eq $item)
    {
      $found = 1;
    }
  }
  if(! $found)
  {
    push @{ $asa_objects{$object}{$reference} }, $item;
  }
}
