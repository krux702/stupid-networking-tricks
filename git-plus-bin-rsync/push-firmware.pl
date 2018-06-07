#!/usr/bin/perl
#
#
# does an rsync of the firmware directory to repo-server.

if($ARGV[0] eq "--delete")
{
  $options = "--delete ";
}

$git_repo = "infrastructure";
$firmware_directory = "repo-server.example.com:/pub/inf/firmware";

$basedir = $ENV{PWD} . "/" . $0;
$basedir =~ s/($git_repo)(|[^\/]+)\/.*/\1/;

if(!-d "$basedir" . "/.git")
{
  print STDERR "Error: Unable to locate $git_repo git repository.\n";
  exit;
}

$sync_command = "rsync -rltD --progress $options${basedir}/firmware/ ${firmware_directory}/";

print "$sync_command\n";

exec($sync_command) or print STDERR "Error: Failed to run rsync.";
