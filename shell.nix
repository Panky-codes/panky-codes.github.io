{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.ruby
    pkgs.bundler
    pkgs.gnumake
    pkgs.gcc
    pkgs.zlib
    pkgs.libffi
    pkgs.libxml2
    pkgs.libxslt
  ];

  shellHook = ''
    export GEM_HOME=$PWD/.gem
    export PATH=$GEM_HOME/bin:$PATH
  '';
}
