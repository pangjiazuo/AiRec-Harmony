param(
    [string]$DevEcoPath = 'C:\Program Files\Huawei\DevEco Studio',
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$AppManifest = Get-Content -LiteralPath (Join-Path $ProjectRoot 'AppScope\app.json5') -Raw
$VersionMatch = [regex]::Match($AppManifest, '"versionName"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
if (-not $VersionMatch.Success) { throw 'AppScope/app.json5 缺少有效 versionName' }
$AppVersion = $VersionMatch.Groups[1].Value
$NodeExe = Join-Path $DevEcoPath 'tools\node\node.exe'
$HvigorScript = Join-Path $DevEcoPath 'tools\hvigor\bin\hvigorw.js'
$Ohpm = Join-Path $DevEcoPath 'tools\ohpm\bin\ohpm.bat'
foreach ($RequiredTool in @($NodeExe, $HvigorScript, $Ohpm)) {
    if (-not (Test-Path -LiteralPath $RequiredTool)) { throw "缺少 DevEco 工具：$RequiredTool" }
}
$OriginalPath = $env:PATH
$OriginalJavaHome = $env:JAVA_HOME
$OriginalNodeHome = $env:NODE_HOME
$OriginalSdkHome = $env:DEVECO_SDK_HOME
try {
    $env:JAVA_HOME = Join-Path $DevEcoPath 'jbr'
    $env:NODE_HOME = Join-Path $DevEcoPath 'tools\node'
    $env:DEVECO_SDK_HOME = Join-Path $DevEcoPath 'sdk'
    $env:PATH = "$env:NODE_HOME;$env:JAVA_HOME\bin;$OriginalPath"
    Push-Location -LiteralPath $ProjectRoot
    try {
        # 路径仅保存在本地忽略文件中，仓库不依赖开发者用户名。
        $SdkPath = (Join-Path $DevEcoPath 'sdk').Replace('\', '/')
        [IO.File]::WriteAllText((Join-Path $ProjectRoot 'local.properties'), "sdk.dir=$SdkPath`n", [Text.UTF8Encoding]::new($false))
        if (-not $SkipInstall) {
            & $Ohpm install
            if ($LASTEXITCODE -ne 0) { throw 'ohpm 依赖安装失败' }
        }
        $DistRoot = Join-Path $ProjectRoot 'dist'
        [IO.Directory]::CreateDirectory($DistRoot) | Out-Null
        $BuildLog = Join-Path $DistRoot "build-$Mode.log"
        $HapOutput = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'entry\build\default\outputs\default'))
        $WorkspacePrefix = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
        if (-not $HapOutput.StartsWith($WorkspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'HAP 输出目录不在当前工程内'
        }
        if (Test-Path -LiteralPath $HapOutput) {
            # 先归档旧包，避免取消签名后误导出上轮残留的 signed HAP。
            $OldHaps = @(Get-ChildItem -LiteralPath $HapOutput -File -Filter '*.hap')
            if ($OldHaps.Count -gt 0) {
                $Archive = Join-Path $ProjectRoot ('.local\previous-haps\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
                [IO.Directory]::CreateDirectory($Archive) | Out-Null
                foreach ($OldHap in $OldHaps) {
                    if (-not $OldHap.FullName.StartsWith($WorkspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw '旧 HAP 路径越界' }
                    Move-Item -LiteralPath $OldHap.FullName -Destination (Join-Path $Archive $OldHap.Name)
                }
            }
        }
        & $NodeExe $HvigorScript --mode module -p product=default -p module=entry@default -p "buildMode=$Mode" assembleHap --no-daemon 2>&1 | Tee-Object -FilePath $BuildLog
        $BuildExit = $LASTEXITCODE
        if ($BuildExit -ne 0) { throw "Hvigor 构建失败（退出码 $BuildExit），日志：$BuildLog" }
        $SignedHap = Get-ChildItem -LiteralPath $HapOutput -Filter '*-signed.hap' | Select-Object -First 1
        $BuiltHap = if ($SignedHap) { $SignedHap } else { Get-ChildItem -LiteralPath $HapOutput -Filter '*-unsigned.hap' | Select-Object -First 1 }
        if (-not $BuiltHap) { throw '没有找到构建后的 HAP' }
        $SignatureLabel = if ($SignedHap) { 'signed' } else { 'unsigned' }
        $Destination = Join-Path $DistRoot "smart-recorder-$AppVersion-$Mode-$SignatureLabel.hap"
        Copy-Item -LiteralPath $BuiltHap.FullName -Destination $Destination -Force
        $Hash = Get-FileHash -LiteralPath $Destination -Algorithm SHA256
        [IO.File]::WriteAllText((Join-Path $DistRoot 'SHA256SUMS'), "$($Hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($Destination))`n", [Text.UTF8Encoding]::new($false))
        Write-Output "构建成功：$Destination"
        if (-not $SignedHap) { Write-Output '此包适用于本地模拟器；真机分发需在 DevEco Studio 配置 HarmonyOS 调试或发布签名。' }
    } finally { Pop-Location }
} finally {
    $env:PATH = $OriginalPath
    $env:JAVA_HOME = $OriginalJavaHome
    $env:NODE_HOME = $OriginalNodeHome
    $env:DEVECO_SDK_HOME = $OriginalSdkHome
}
