# Every module below a directory: each .nix file except default.nix, and each
# subdirectory that has a default.nix. Other subdirectories are searched too.
let
  findModules =
    dir:
    builtins.concatMap (
      name:
      let
        path = dir + "/${name}";
        type = (builtins.readDir dir).${name};
      in
      if type == "directory" then
        if builtins.pathExists (path + "/default.nix") then [ path ] else findModules path
      else if name != "default.nix" && builtins.match ".*\\.nix" name != null then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames (builtins.readDir dir));
in
findModules
