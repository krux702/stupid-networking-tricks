I needed to generate Cisco Type 9 password hashes using Python, so this has been converted from
code found in John the Ripper.

It generates a Cisco Type 9 password hash the same as you would get were you to type the command

router(config)# username <username> priv 15 algorithm-type scrypt secret <password>


Also you should be using scrypt on your Cisco network devices if they support it for local accounts.

See the following forum post:

https://community.cisco.com/t5/security-documents/why-you-should-be-using-scrypt-for-cisco-router-password-storage/ta-p/3157196
