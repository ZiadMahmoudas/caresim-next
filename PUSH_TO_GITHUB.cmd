@echo off
setlocal
cd /d "%~dp0"

echo =============================================
echo CareSim Neon - Safe GitHub Push
echo =============================================

if not exist .git (
  git init
  if errorlevel 1 goto :error
  git branch -M main
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
  echo No GitHub remote is configured yet.
  echo Add it first with:
  echo git remote add origin YOUR_GITHUB_REPO_URL
  goto :error
)

git add .
if errorlevel 1 goto :error

git commit -m "Migrate CareSim backend to Neon"
if errorlevel 1 (
  echo No new commit was created. If there are no changes, this is normal.
)

git push -u origin main
if errorlevel 1 goto :error

echo.
echo SUCCESS: Push completed without force-pushing.
pause
exit /b 0

:error
echo.
echo Push was not completed. Read the Git message above.
pause
exit /b 1
