#!/usr/bin/perl
#
#
# does an rsync of the firmware directory on repo-server.

$git_repo = "infrastructure";
$firmware_directory = "repo-server.example.com:/pub/inf/firmware";

$basedir = $ENV{PWD} . "/" . $0;
$basedir =~ s/($git_repo)(|[^\/]+)\/.*/\1/;

if(!-d "$basedir" . "/.git")
{
  print STDERR "Error: Unable to locate $git_repo git repository.\n";
  exit;
}

$sync_command = "rsync -rltD --progress --delete ${firmware_directory} ${basedir}/";

print "$sync_command\n";

exec($sync_command) or print STDERR "Error: Failed to run rsync.";
