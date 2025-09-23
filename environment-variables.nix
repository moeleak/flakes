{ config, pkgs, ... }:

{
  environment.variables = {
    EDITOR = "nvim";
    OPENAI_API_KEY = "sk-xxx";
  };
}
