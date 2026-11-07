<#
  One-time setup for the GitHub release workflow
  (.github/workflows/release.yml).

  The release is built on GitHub, which doesn't have the files git ignores
  (Firebase config, the Windows Google sign-in client, the Android signing
  key). This script reads them from THIS PC and stores them as GitHub
  Actions secrets with the gh CLI. Nothing is printed or committed.

  Run from the CruDoc folder, signed in to gh (gh auth login):

      ./tool/setup_release_secrets.ps1

  Android signing key: by default your PC's debug key. Phones that have
  CruDoc installed from your local builds are signed with it, so releases
  update them in place with no uninstall. Every release must keep using the
  same key. To use your own release keystore instead, pass -Keystore,
  -KeyAlias, -StorePassword and -KeyPassword. (A phone that has the app
  signed with a different key must uninstall it once first.)

  Optional: the Google Maps key, if your release should have maps:

      gh secret set GOOGLE_MAPS_API_KEY --repo CruciaTos/Svayatta-CruDoc
#>
param(
  [string]$Repo = 'CruciaTos/Svayatta-CruDoc',
  [string]$Keystore = (Join-Path $env:USERPROFILE '.android\debug.keystore'),
  [string]$KeyAlias = 'androiddebugkey',
  [string]$StorePassword = 'android',
  [string]$KeyPassword = 'android'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw 'The GitHub CLI (gh) is not installed. Get it from https://cli.github.com'
}
gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Sign in first: gh auth login' }

function Set-FileSecret([string]$Name, [string]$Path) {
  if (-not (Test-Path $Path)) { throw "Missing file: $Path" }
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $Path)))
  $b64 | gh secret set $Name --repo $Repo
  if ($LASTEXITCODE -ne 0) { throw "Could not set $Name" }
  Write-Host "set $Name"
}

function Set-TextSecret([string]$Name, [string]$Value) {
  $Value | gh secret set $Name --repo $Repo
  if ($LASTEXITCODE -ne 0) { throw "Could not set $Name" }
  Write-Host "set $Name"
}

Set-FileSecret 'GOOGLE_SERVICES_JSON_BASE64' 'android/app/google-services.json'
Set-FileSecret 'FIREBASE_OPTIONS_DART_BASE64' 'lib/firebase_options.dart'
Set-FileSecret 'GOOGLE_DESKTOP_OAUTH_JSON_BASE64' 'google_desktop_oauth.json'
Set-FileSecret 'ANDROID_KEYSTORE_BASE64' $Keystore
Set-TextSecret 'ANDROID_KEYSTORE_PASSWORD' $StorePassword
Set-TextSecret 'ANDROID_KEY_ALIAS' $KeyAlias
Set-TextSecret 'ANDROID_KEY_PASSWORD' $KeyPassword

Write-Host ''
Write-Host 'Done. Release with:  git tag v1.0.1 ; git push origin v1.0.1'
Write-Host 'or GitHub > Actions > Release > Run workflow.'
