#!/usr/bin/python3
'''
Generates a Cisco Type 9 password hash the same as you would get were you to type the command

router(config)# username <username> priv 15 algorithm-type scrypt secret <password>

'''

import sys
import random
import scrypt

def cisco_type9(pt):
  # Generate Cisco Type 9 Scrypt password hash
  itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  salt = ''.join(random.choice(itoa64) for i in range(14))
  key = scrypt.hash(pt, salt, 16384, 1, 1, 32)
  keystr = base64_wpa(key)
  hash = "$9$" + salt + "$" + keystr
  return hash

def crypt_to64_wpa(v, n):
  itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  out = ""
  while n > 0:
    n -= 1
    vval = (v & 0xFC0000)>>18
    out = out + itoa64[vval]
    v <<= 6
  return out

def base64_wpa(final):
  len_final = len(final)
  mod = len_final % 3
  cnt = int((len_final - mod) / 3)
  out = ""
  for i in range(0, cnt):
    l = (final[(i * 3)] << 16) | (final[(i * 3 + 1)] << 8) | (final[(i * 3 + 2)])
    l1 = (final[(i * 3)] << 16)
    l2 = (final[(i * 3 + 1)] << 8)
    l3 = (final[(i * 3 + 2)])
    out = out + crypt_to64_wpa(l, 4)
  i += 1
  if mod == 2:
    l = (final[(i * 3)] << 16) | (final[(i * 3 + 1)] << 8)
    l1 = (final[(i * 3)] << 16)
    l2 = (final[(i * 3 + 1)] << 8)
    out = out + crypt_to64_wpa(l, 3)
  if mod == 1:
    l = (final[(i * 3)] << 16)
    out = out + crypt_to64_wpa(l, 2)

  return out

if(len(sys.argv) >= 2):
  print(cisco_type9(sys.argv[1]))
else:
  print("Syntax: ./generate_type9.py <passsword>")
