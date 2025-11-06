%build
cd %{_builddir}/buildtools/install/common
bash systemd/build.sh -pm "rpm"
bash plugins-build.sh %{_builddir}/plugins
bash packages-build.sh rpm %{_builddir} %{product} "%{version}.%{release}"

find %{_builddir}/publish/ -type f -regex '.*\.so$' -exec chmod 755 {} \; -exec strip {} \;
find %{_builddir}/publish/ -type f -regex '.*\.\(dll\|dylib\)$' -exec chmod 755 {} \;
