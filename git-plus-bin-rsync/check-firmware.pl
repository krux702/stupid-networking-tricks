#!/usr/bin/perl
#
# compares remote repo on repo-server with local, and displays changes which would be made
# files listed exist on remote but not local
# files shown as being deleted exist locally but not remote

$git_repo = "infrastructure";
$firmware_directory = "repo-server.example.com:/pub/inf/firmware";

$basedir = $ENV{PWD} . "/" . $0;
$basedir =~ s/($git_repo)(|[^\/]+)\/.*/\1/;

if(!-d "$basedir" . "/.git")
{
  print STDERR "Error: Unable to locate $git_repo git repository.\n";
  exit;
}

$sync_command = "rsync -rltDn --progress --delete ${firmware_directory}/* ${basedir}/firmware/";

print "$sync_command\n";

print "\nNote: Files marked to be deleted exist locally but are not in the central repo.\n\n"; 

exec($sync_command) or print STDERR "Error: Failed to run rsync.";

