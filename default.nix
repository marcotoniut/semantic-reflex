let obelisk = import ./obelisk {};
in obelisk.reflex-platform.project ({ pkgs, ... }: {
  packages = {
    semantic-reflex = ./semantic-reflex;
    semantic-reflex-example = ./semantic-reflex-example;
  };

  shells = {
    ghc = ["semantic-reflex" "semantic-reflex-example"];
    ghcjs = ["semantic-reflex" "semantic-reflex-example"];
  };
})
