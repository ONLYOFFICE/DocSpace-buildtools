@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\web\ASC.Web.HealthChecks.UI\bin\Debug\ASC.Web.HealthChecks.UI.exe urls=http://0.0.0.0:5033