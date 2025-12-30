{ ... }:

{
  services.samba = {
    enable = true;
    settings = {
      Share = {
        path = "/home/moeleak/Share";
        browseable = true;
        writable = true;
        guestOk = true;
      };
    };
  };
}
