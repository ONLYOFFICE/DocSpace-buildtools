%build

cd %{_builddir}/buildtools

bash install/common/systemd/build.sh -pm "rpm"

bash install/common/build-frontend.sh --srcpath %{_builddir} -di "false"
bash install/common/build-backend.sh --srcpath %{_builddir}
bash install/common/publish-backend.sh --srcpath %{_builddir}/server
bash install/common/plugins-build.sh %{_builddir}/plugins
bash install/common/packages-build.sh rpm %{_builddir} %{product}

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(dll\|dylib\|so\)$' -exec chmod 755 {} \;

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(so\)$' -exec strip {} \;
