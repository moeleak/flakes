{ pkgs, ... }:
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

  virtualisation.docker.enable = true;

  services.minecraft-server = {
    enable = true;
    package = pkgs.papermc;
    eula = true;
    declarative = true;
    serverProperties = {
      server-port = 25565;
      difficulty = 3;
      gamemode = 0;
      max-players = 20;
      motd = "Minecraft Server on RISC-V";
      white-list = false;
      allow-cheats = false;
    };
    jvmOpts = "-Xms4096M -Xmx4096M";
  };

  # System monitor, published as lp4a.leak.moe through the tunnel below.
  services.glances = {
    enable = true;
    port = 8000;
  };

  services.cloudflared = {
    enable = true;
    tunnels."7f917902-fe32-4b56-b8e4-81532b5208e2" = {
      credentialsFile = "/home/moeleak/.cloudflared/7f917902-fe32-4b56-b8e4-81532b5208e2.json";
      ingress."lp4a.leak.moe" = "http://localhost:8000";
      default = "http_status:404";
    };
  };
}
