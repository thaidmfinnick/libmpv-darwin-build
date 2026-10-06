{
  pkgs ? import ../../utils/default/pkgs.nix,
  os ? import ../../utils/default/os.nix,
  arch ? pkgs.callPackage ../../utils/default/arch.nix { },
}:

let
  name = "libplacebo";
  packageLock = (import ../../../packages.lock.nix).${name};
  inherit (packageLock) version;

  callPackage = pkgs.lib.callPackageWith { inherit pkgs os arch; };
  nativeFile = callPackage ../../utils/native-file/default.nix { };
  crossFile = callPackage ../../utils/cross-file/default.nix { };

  # The release tarball does not contain the git submodules (glad, jinja,
  # markupsafe, fast_float), so provide them from the build environment
  python = pkgs.python3.withPackages (ps: [
    ps.glad2
    ps.jinja2
  ]);

  pname = import ../../utils/name/package.nix name;
  src = callPackage ../../utils/fetch-tarball/default.nix {
    name = "${pname}-source-${version}";
    inherit (packageLock) url sha256;
  };
  patchedSource = pkgs.runCommand "${pname}-patched-source-${version}" { } ''
    cp -r ${src} src
    export src=$PWD/src
    chmod -R 777 $src

    cd $src
    # use the python packages from the build environment instead of the
    # (empty) git submodules
    sed -i "/python_env.append/d" meson.build

    mkdir -p 3rdparty/fast_float/include
    cp -r ${pkgs.fast-float}/include/fast_float 3rdparty/fast_float/include/

    # the vulkan stubs need the headers even when vulkan is disabled
    mkdir -p 3rdparty/Vulkan-Headers/registry
    cp -r ${pkgs.vulkan-headers}/include 3rdparty/Vulkan-Headers/
    cp ${pkgs.vulkan-headers}/share/vulkan/registry/vk.xml 3rdparty/Vulkan-Headers/registry/
    cd -

    cp -r $src $out
  '';
in

pkgs.stdenvNoCC.mkDerivation {
  name = "${pname}-${os}-${arch}-${version}";
  pname = pname;
  inherit version;
  src = patchedSource;
  dontUnpack = true;
  enableParallelBuilding = true;
  nativeBuildInputs = [
    pkgs.meson
    pkgs.ninja
    pkgs.pkg-config
    python
  ];
  configurePhase = ''
    export PYTHONPATH=${python}/${python.sitePackages}

    meson setup build $src \
      --native-file ${nativeFile} \
      --cross-file ${crossFile} \
      --prefix=$out \
      -Dvulkan=disabled \
      -Dvk-proc-addr=disabled \
      -Dopengl=enabled \
      -Dgl-proc-addr=enabled \
      -Dd3d11=disabled \
      -Dglslang=disabled \
      -Dshaderc=disabled \
      -Dlcms=disabled \
      -Ddovi=enabled \
      -Dlibdovi=disabled \
      -Dxxhash=disabled \
      -Dunwind=disabled \
      -Ddemos=false \
      -Dtests=false \
      -Dbench=false \
      -Dfuzz=false \
      -Ddebug-abort=false
  '';
  buildPhase = ''
    meson compile -vC build
  '';
  installPhase = ''
    meson install -C build
  '';
}
