@echo off
echo 
echo #####################
echo #   build backend   #
echo #####################

rem .NET services and the migration runner are built once in Release by publish-script.bat
rem The node services keep only production dependencies: the lockfile is checked first, then dev dependencies are dropped

pushd %~1

  echo "== Build ASC.Socket.IO =="
  pushd common\ASC.Socket.IO
    call yarn install --frozen-lockfile
    call yarn workspaces focus --production
  popd

  echo "== Build ASC.AI.Chat =="
  pushd common\ASC.AI.Chat
    call yarn install --frozen-lockfile
    call yarn workspaces focus --production
  popd

  echo "== Build ASC.SsoAuth =="
  pushd common\ASC.SsoAuth
    call yarn install --frozen-lockfile
    call yarn workspaces focus --production
  popd

  echo "== Build ASC.Identity =="
  pushd common\ASC.Identity

    echo "== Build ASC.Identity.Authorization =="
    call mvn clean package -DskipTests -pl authorization/authorization-container -am

    echo "== Build ASC.Identity.Registration =="
    call mvn clean package -DskipTests -pl registration/registration-container -am

  popd

popd
