{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  nativeBuildInputs = with pkgs.buildPackages; [
    go
    go-task
    yamlfmt
    shfmt
    opentofu
    awscli
    age
    sops
    ansible
  ];
}
