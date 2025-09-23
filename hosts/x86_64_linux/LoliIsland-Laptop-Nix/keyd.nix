{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            meta = "overload(control, esc)";
          };
        };
      };
    };
  };
}
