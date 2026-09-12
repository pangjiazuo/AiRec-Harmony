$ErrorActionPreference = 'Stop'
$Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Target = [IO.Path]::GetFullPath((Join-Path $Project '.local\signing-smoke'))
if (-not $Target.StartsWith($Project.TrimEnd('\') + '\.local\', [StringComparison]::OrdinalIgnoreCase)) { throw '隔离工程路径越界' }
[IO.Directory]::CreateDirectory($Target) | Out-Null
foreach ($Folder in @('AppScope', 'entry\src', 'hvigor')) {
    $Destination = Join-Path $Target $Folder
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Destination)) | Out-Null
    # Copy-Item 到父目录会保留 src 层级，避免产生 src/src。
    Copy-Item -LiteralPath (Join-Path $Project $Folder) -Destination (Split-Path -Parent $Destination) -Recurse -Force
}
foreach ($File in @('build-profile.json5', 'hvigorfile.ts', 'oh-package.json5', 'build-hap.ps1',
    'entry\build-profile.json5', 'entry\hvigorfile.ts', 'entry\oh-package.json5')) {
    Copy-Item -LiteralPath (Join-Path $Project $File) -Destination (Join-Path $Target $File) -Force
}
$ManifestPath = Join-Path $Target 'AppScope\app.json5'
$Manifest = [IO.File]::ReadAllText($ManifestPath).Replace('com.neardi.recorder', 'com.neardi.recorder.tests')
[IO.File]::WriteAllText($ManifestPath, $Manifest, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TimelineTestAbility.ets.txt') -Destination (Join-Path $Target 'entry\src\main\ets\entryability\EntryAbility.ets') -Force
Write-Output "已同步隔离源码：$Target（尚未构建或启动模拟器）"
