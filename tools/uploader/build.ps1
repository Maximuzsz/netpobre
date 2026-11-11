$ErrorActionPreference = 'Stop'

$UploaderDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Resolve-Path (Join-Path $UploaderDir '..\..')
$DistDir = Join-Path $RepoDir 'build\uploader'
$IconPng = Join-Path $RepoDir 'assets\branding\netpobre-icon-1024.png'
$MascotPng = Join-Path $RepoDir 'assets\branding\netpobre-mascot-transparent.png'
$IconIco = Join-Path $UploaderDir 'netpobre-icon.ico'

python -m pip install -r (Join-Path $UploaderDir 'requirements.txt')

@"
from PIL import Image
image = Image.open(r'$IconPng').convert('RGBA')
image.save(r'$IconIco', format='ICO', sizes=[(16,16), (24,24), (32,32), (48,48), (64,64), (128,128), (256,256)])
"@ | python -

python -m PyInstaller `
  --noconfirm `
  --clean `
  --onefile `
  --windowed `
  --name 'NetPobre-Enviar' `
  --icon $IconIco `
  --add-data "${MascotPng};." `
  --add-data "${IconIco};." `
  --distpath $DistDir `
  --workpath (Join-Path $RepoDir 'build\uploader-work') `
  --specpath (Join-Path $RepoDir 'build') `
  (Join-Path $UploaderDir 'netpobre_uploader.py')

Write-Host "Criado: $(Join-Path $DistDir 'NetPobre-Enviar.exe')"
