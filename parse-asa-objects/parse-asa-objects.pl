#!/usr/bin/perl

use Data::Dumper;

# item{name} = (  parents => [...],
#                children => [...] )

($filename) = @ARGV;

if(!$filename)
{
  print "Reads in the configuration of an ASA firewall, and displays the objects,
and their relationship to one another.  Indicates objects which are not referenced
by any ACLs for potiential firewall cleanup.

SYNTAX:

./parse-asa-objects <template_name>

";

  exit;
}



%asa_objects = ();
$current_object = "";

open (FILE, "<$filename");

while(<FILE>)
{
  if($_ =~ /^object-group (network|service) ([a-zA-Z0-9\._-]*)/)
  {
    $current_object = $2;
    $asa_objects{$current_object}{'parents'} = [];
    $asa_objects{$current_object}{'children'} = [];
  }
  if($_ =~ /^ group-object (.*)$/)
  {
     push @{ $asa_objects{$1}{'parents'}}, $current_object;
     push @{ $asa_objects{$current_object}{'children'}}, $1;
  }

  if($_ =~ /^access-list (.*) extended .*/ )
  {
    $current_object = $1;
    $asa_objects{$current_object}{'parents'} = ["ACL"];
    $asa_objects{$current_object}{'children'} = [];

    $acl = $_;
    while($acl =~ s/(object-group) ([^\ ]*)//)
    {
      push @{ $asa_objects{$2}{'parents'}}, $current_object;
      push @{ $asa_objects{$current_object}{'children'}}, $2;
    }
  }
}

close(FILE);

# print Dumper(\%item);
print Data::Dumper->Dump( [ \%asa_objects ], [ qw(*asa_objects) ] );


print "\n------------\n";
print "Unreferenced\n";
print "------------\n";

foreach $key (keys %asa_objects)
{
  $parents = $#{$asa_objects{$key}{'parents'}};
  if($parents eq -1)
  {
    print "$key\n";
  }
}

