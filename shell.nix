{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  buildInputs = with pkgs; [
    cmake
    pkg-config
    gtk3
    xz
    clang
    ninja
    libGLU
    libsysprof-capture
    pcre2.dev
    util-linux.dev
    libselinux
    libsepol
    libthai
    libdatrie
    xorg.libXdmcp
    xorg.libXtst
    lerc.dev
    libxkbcommon
    libepoxy
    libz
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.libepoxy
    pkgs.fontconfig
    pkgs.gtk3
    pkgs.glib
    pkgs.libGL
    pkgs.libz
    pkgs.libdeflate
  ];

  shellHook = ''
    export CHROME_EXECUTABLE="${pkgs.ungoogled-chromium}/bin/chromium"
  '';

}
