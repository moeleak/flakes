{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
let
  alsa-ucm-conf-cros =
    with pkgs;
    alsa-ucm-conf.overrideAttrs {
      wttsrc = fetchFromGitHub {
        owner = "WeirdTreeThing";
        repo = "alsa-ucm-conf-cros";
        rev = "a4e9213";
        hash = "sha256-3TpzjmWuOn8+eIdj0BUQk2TeAU7BzPBi3FxAmZ3zkN8=";
      };
      postInstall = ''
        rm -f $out/share/alsa/ucm2/conf.d/avs_dmic/Google-Atlas-1.0.conf
      '';
      unpackPhase = ''
        runHook preUnpack
        tar xf "$src"
        runHook postUnpack
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/alsa
        cp -r alsa-ucm*/ucm2 $out/share/alsa
        runHook postInstall
      '';
    };
in
{

  system.replaceDependencies.replacements = [
    {
      original = pkgs.alsa-ucm-conf;
      replacement = alsa-ucm-conf-cros;
    }
  ];
  services.pipewire.wireplumber.extraConfig = {
    "increase-headroom" = {
      "monitor.alsa.rules" = [
        {
          matches = [
            {
              "node.name" = "~alsa_output.*";
            }
          ];
          actions = {
            update-props = {
              "api.alsa.headroom" = "4096";
            };
          };
        }
      ];
    };
  };
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=4
    options snd-soc-avs ignore_fw_version=1
    options snd-soc-avs obsolete_card_names=1
  '';
}
