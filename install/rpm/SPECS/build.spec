%build
run_script() { start=$(date +%s.%N) && bash "$@"; echo "::notice::$1 completed in $(printf "%.0f\n" $(echo "$(date +%s.%N) - $start" | bc -l)) seconds"; }

cd %{_builddir}/buildtools

run_script install/common/build-frontend.sh --srcpath %{_builddir} -di "false"
run_script install/common/build-backend.sh --srcpath %{_builddir}
run_script install/common/publish-backend.sh --srcpath %{_builddir}/server
run_script install/common/plugins-build.sh %{_builddir}/plugins
run_script install/common/systemd/build.sh -pm "rpm"
run_script install/common/packages-build.sh rpm %{_builddir} %{product}

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(dll\|dylib\|so\)$' -exec chmod 755 {} \;

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(so\)$' -exec strip {} \;
