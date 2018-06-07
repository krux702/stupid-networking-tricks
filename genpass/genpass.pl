#!/usr/bin/perl

@pool = split(//,'abcdefghijkmnopqrstuvwxyzABCDEFGHIJKLMNPQRSTUVWXYZ234567890');

# regular punctuation
# @special = split(//,'~@#$%^&*()-_+[{]};:,<.>/');

# non-breaking punctuation which can be selected with a double-click
@special = split(//,'~@#%&-_+=:,./');

($len,$count,$spec,$exp) = @ARGV;

if($len eq "--help")
{
  print "Usage\n\n$0 [length] [count] [special] [all punctuation]\n\n";
  print "By default $0 called by itself will generate 1 password, 32 characters in length,\n";
  print "with 2 non-breaking (can be selected using double click) special characters.\n\n";
  exit;
}

if($len < 1)
{
  $len = 32;
}
if($count < 1)
{
  $count = 1;
}
if($spec < 1)
{
  $spec = 2;
}
if($exp)
{
  # regular punctuation
  # @special = split(//,'~@#$%^&*()-_+[{]};:,<.>/');
}


print "Generating $count of $len length passwords.\n\n";

for ($y = 0 ; $y < $count ; $y++)
{
  $pass = "";
  for ($n = 0 ; $n < $len - $spec ; $n++)
  {
    $pass .= $pool[rand(scalar(@pool))];
  }
  
  # add special characters
  for ($n = 0 ; $n < $spec ; $n++)
  {
    $split = rand($len + $n - $spec - 1);
    $a = substr($pass, 0, $split + 1);
    $b = substr($pass, $split + 1);
    $pass = $a . $special[rand(scalar(@special))] . $b;
  }
  print "$pass\n";
}
