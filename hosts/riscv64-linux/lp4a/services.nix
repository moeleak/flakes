{ ... }:
{
  services.openssh = {
    enable = true;
    ports = [ 2333 ];
    settings = {
      X11Forwarding = true;
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };
}
