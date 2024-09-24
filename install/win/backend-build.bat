@echo off
echo 
echo #####################
echo #   build backend   #
echo #####################

set SRC_PATH=%~s2

pushd %~1

  call dotnet build ASC.Web.slnf
  call dotnet build ASC.Migrations.sln --property:OutputPath=%SRC_PATH%\services\ASC.Migration.Runner\service

  echo "== Build ASC.Socket.IO =="
  pushd common\ASC.Socket.IO
    call yarn install --frozen-lockfile
  popd

  echo "== Build ASC.SsoAuth =="
  pushd common\ASC.SsoAuth
    call yarn install --frozen-lockfile
  popd

  echo "== Build ASC.Identity =="
  pushd common\ASC.Identity

    echo "== Build ASC.Identity.Authorization =="
    call mvn clean package -DskipTests -pl authorization/authorization-container -am

    echo "== Build ASC.Identity.Registration =="
    call mvn clean package -DskipTests -pl registration/registration-container -am

    echo "== Build ASC.Identity.Migration =="
    call mvn clean package -DskipTests -pl infrastructure/infrastructure-migration-runner -am

  popd

popd
