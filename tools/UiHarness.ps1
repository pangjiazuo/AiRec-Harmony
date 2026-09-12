param(
    [string]$Target = '127.0.0.1:12345',
    [string]$DevEcoPath = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '..\dist\verification-20260908')
)
$RecorderHdcExe = Join-Path $DevEcoPath 'sdk\default\openharmony\toolchains\hdc.exe'
$RecorderTestTarget = $Target
$RecorderEvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
[IO.Directory]::CreateDirectory($RecorderEvidenceDirectory) | Out-Null

function Invoke-RecorderHdc {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $Result = & $RecorderHdcExe -t $RecorderTestTarget @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "hdc 命令失败：$($Arguments -join ' ')；$Result" }
    $ResultText = $Result -join "`n"
    if ($ResultText -match '(?im)^\[Fail\]|^error:|^Error Code:|^failed to') {
        throw "hdc 返回失败：$ResultText"
    }
    return $ResultText
}

function Get-RecorderLayout {
    param([string]$Name = 'current-layout')
    $RemotePath = '/data/local/tmp/smart-recorder-test-layout.json'
    $LocalPath = Join-Path $RecorderEvidenceDirectory "$Name.json"
    $null = Invoke-RecorderHdc @('shell', 'uitest', 'dumpLayout', '-p', $RemotePath)
    $null = Invoke-RecorderHdc @('file', 'recv', $RemotePath, $LocalPath)
    return (Get-Content -LiteralPath $LocalPath -Raw -ErrorAction Stop | ConvertFrom-Json)
}

function Get-RecorderNodes {
    param([Parameter(Mandatory)][AllowNull()]$Node)
    # 模拟器正在切换页面时可能短暂返回 null，交由上层有界等待重试。
    if ($null -eq $Node) { return }
    $Node.attributes
    foreach ($Child in $Node.children) { Get-RecorderNodes $Child }
}

function Find-RecorderNode {
    param([string]$Id, [string]$Text, $Layout)
    if (-not $Layout) { $Layout = Get-RecorderLayout }
    $Nodes = @(Get-RecorderNodes $Layout)
    if ($Id) { return $Nodes | Where-Object { $_.id -eq $Id -and $_.visible -ne 'false' } | Select-Object -First 1 }
    return $Nodes | Where-Object { $_.text -eq $Text -and $_.visible -ne 'false' } | Select-Object -First 1
}

function Wait-RecorderNode {
    param([string]$Id, [string]$Text, [int]$TimeoutSeconds = 20)
    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $Node = Find-RecorderNode -Id $Id -Text $Text
        if ($Node) { return $Node }
        Start-Sleep -Milliseconds 400
    } while ([DateTime]::UtcNow -lt $Deadline)
    throw "等待界面元素超时：id=$Id；text=$Text"
}

function Click-RecorderNode {
    param([string]$Id, [string]$Text, $Node)
    if (-not $Node -and -not $Id -and -not $Text) { throw '没有有效点击目标，禁止点击未定位的区域' }
    if (-not $Node) { $Node = Wait-RecorderNode -Id $Id -Text $Text }
    if ($Node.enabled -eq 'false') { throw "控件不可用：$($Node.id) $($Node.text)" }
    if ($Node.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') { throw "无法解析控件边界：$($Node.bounds)" }
    $CenterX = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
    $CenterY = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    $null = Invoke-RecorderHdc @('shell', 'uitest', 'uiInput', 'click', "$CenterX", "$CenterY")
}

function Save-RecorderScreenshot {
    param([Parameter(Mandatory)][string]$Name)
    $RemotePath = '/data/local/tmp/smart-recorder-test-screen.png'
    $LocalPath = Join-Path $RecorderEvidenceDirectory "$Name.png"
    $null = Invoke-RecorderHdc @('shell', 'uitest', 'screenCap', '-p', $RemotePath)
    $null = Invoke-RecorderHdc @('file', 'recv', $RemotePath, $LocalPath)
    if (-not (Test-Path -LiteralPath $LocalPath)) { throw '截图文件未返回' }
    return $LocalPath
}

function Get-RecorderVisibleText {
    param([string]$Name = 'current-layout')
    Get-RecorderNodes (Get-RecorderLayout -Name $Name) | Where-Object { $_.text -and $_.visible -ne 'false' } |
        Select-Object text, id, bounds, type, enabled
}
