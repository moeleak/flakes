# AS4242423914 (Kioubit.dn42), its us3-lax node. Its automatic peering
# expects fe80::ade1 on our side: it connects there, and resets a session
# from any other address.
{
  asn = 4242423914;
  endpoint = "us3.g-load.eu:20085";
  publicKey = "sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8=";
  linkLocal = "fe80::ade0";
  localLinkLocal = "fe80::ade1";
}
