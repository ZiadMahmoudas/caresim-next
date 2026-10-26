@echo off
setlocal
cd /d "%~dp0"

echo =============================================
echo CareSim - Clean GitHub Push
echo =============================================

echo.
echo Checking that secret/local files are not tracked...
if exist .git rmdir /s /q .git

git init
if errorlevel 1 goto :error

git branch -M main

git remote add origin https://github.com/ZiadMahmoudas/caresim-next.git
if errorlevel 1 goto :error

git add .
if errorlevel 1 goto :error

echo.
echo Files staged. Verifying ignored files...
git status --short

git commit -m "CareSim production release"
if errorlevel 1 goto :error

echo.
echo Pushing to GitHub...
git push -u origin main --force
if errorlevel 1 goto :error

echo.
echo =============================================
echo SUCCESS: GitHub push completed.
echo Repo: https://github.com/ZiadMahmoudas/caresim-next
echo =============================================
pause
exit /b 0

:error
echo.
echo =============================================
echo ERROR: Push did not finish.
echo Read the Git message above.
echo =============================================
pause
exit /b 1
