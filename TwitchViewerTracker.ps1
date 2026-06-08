#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

# ============================================================
#  Walhalla Twitch Viewer Tracker - Touch Portal Plugin
#  by odin23x
# ============================================================

$PluginId  = 'odin23x.walhalla_viewer_tracker'
$LogFile   = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'viewer.log'
$TPHost    = '127.0.0.1'
$TPPort    = 12136

$script:Settings = @{
    'Twitch Client ID'       = ''
    'Twitch OAuth Token'     = ''
    'Broadcaster User ID'    = ''
    'Update Interval Seconds'= '30'
}
$script:TcpClient    = $null
$script:Writer       = $null
$script:Reader       = $null
$script:ForceRefresh = $false
$script:LastCheckUtc = [datetime]::MinValue
$script:LastStates   = @{}

function Write-Log {
    param([string]$Msg)
    $line = '[{0}] {1}' -f ([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')), $Msg
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
    Write-Host $line
}

function Send-TP {
    param([hashtable]$Payload)
    if ($null -eq $script:Writer) { return }
    try {
        $script:Writer.WriteLine(($Payload | ConvertTo-Json -Compress -Depth 5))
        $script:Writer.Flush()
    } catch {}
}

function Set-State {
    param([string]$Id, [string]$Value)
    if ($script:LastStates[$Id] -eq $Value) { return }
    $script:LastStates[$Id] = $Value
    Send-TP @{ type = 'stateUpdate'; id = $Id; value = [string]$Value }
}

function Parse-Settings {
    param($Values)
    foreach ($item in $Values) {
        foreach ($prop in $item.PSObject.Properties) {
            $script:Settings[$prop.Name] = [string]$prop.Value
        }
    }
}

function Get-Interval {
    $v = 30
    [void][int]::TryParse([string]$script:Settings['Update Interval Seconds'], [ref]$v)
    return [Math]::Max(10, [Math]::Min(300, $v))
}

function Run-Check {
    $clientId = [string]$script:Settings['Twitch Client ID']
    $token    = ([string]$script:Settings['Twitch OAuth Token']) -replace '^oauth:', ''
    $uid      = [string]$script:Settings['Broadcaster User ID']

    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($uid)) {
        Set-State "$PluginId.state.status" 'Bitte Client ID, Token und User ID eintragen'
        return
    }

    try {
        $headers = @{ 'Client-ID' = $clientId; 'Authorization' = "Bearer $token" }
        $uri     = "https://api.twitch.tv/helix/chat/chatters?broadcaster_id=$uid&moderator_id=$uid&first=1000"
        $res     = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

        if ($res.data) {
            $names = $res.data.user_name -join "`n"
            $count = [string]$res.total
            if ($names) { Set-State "$PluginId.state.viewer_list"  $names } else { Set-State "$PluginId.state.viewer_list"  'Keine Zuschauer' }
            Set-State "$PluginId.state.viewer_count" $count
        } else {
            Set-State "$PluginId.state.viewer_list"  'Keine Zuschauer'
            Set-State "$PluginId.state.viewer_count" '0'
        }

        Set-State "$PluginId.state.last_update" ([datetime]::Now.ToString('dd.MM.yyyy HH:mm:ss'))
        Set-State "$PluginId.state.status"      'OK'
        $script:LastCheckUtc = [datetime]::UtcNow

    } catch {
        $msg = $_.Exception.Message
        if ($msg -like '*401*') { $msg = 'Token ungültig (401)' }
        elseif ($msg -like '*403*') { $msg = 'Kein Moderator-Zugriff (403)' }
        Set-State "$PluginId.state.status" "Fehler: $msg"
        Write-Log "Run-Check failed: $msg"
    }
}

function Handle-Message {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    try { $msg = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return }
    switch ([string]$msg.type) {
        'info'        { if ($msg.settings) { Parse-Settings $msg.settings }; $script:ForceRefresh = $true }
        'settings'    { if ($msg.values)   { Parse-Settings $msg.values };   $script:LastStates = @{}; $script:ForceRefresh = $true }
        'action'      { if ($msg.actionId -eq "$PluginId.act.refresh") { $script:ForceRefresh = $true } }
        'closePlugin' { throw 'Shutdown' }
    }
}

function Connect-TP {
    while ($true) {
        try {
            $script:TcpClient = New-Object System.Net.Sockets.TcpClient
            $script:TcpClient.Connect($TPHost, $TPPort)
            $enc = New-Object System.Text.UTF8Encoding($false)
            $script:Writer = New-Object System.IO.StreamWriter($script:TcpClient.GetStream(), $enc); $script:Writer.AutoFlush = $true
            $script:Reader = New-Object System.IO.StreamReader($script:TcpClient.GetStream(), $enc)
            Send-TP @{ type = 'pair'; id = $PluginId }
            Write-Log 'Connected to Touch Portal.'
            return
        } catch { Start-Sleep -Seconds 5 }
    }
}

Write-Log '=== Walhalla Twitch Viewer Tracker starting ==='
Connect-TP
Set-State "$PluginId.state.status"      'Startet...'
Set-State "$PluginId.state.viewer_list" 'Warten auf Einstellungen...'
Set-State "$PluginId.state.viewer_count" '0'

while ($true) {
    try {
        while ($script:TcpClient.Available -gt 0 -or $script:Reader.Peek() -ge 0) {
            $line = $script:Reader.ReadLine()
            if ($null -eq $line) { break }
            Handle-Message -Line $line
        }
        $elapsed = ([datetime]::UtcNow - $script:LastCheckUtc).TotalSeconds
        if ($script:ForceRefresh -or $script:LastCheckUtc -eq [datetime]::MinValue -or $elapsed -ge (Get-Interval)) {
            $script:ForceRefresh = $false
            Run-Check
        }
        Start-Sleep -Milliseconds 500
    } catch {
        if ($_.Exception.Message -eq 'Shutdown') { Write-Log 'Shutdown.'; exit 0 }
        Write-Log "Error: $($_.Exception.Message) – reconnecting"
        try { Set-State "$PluginId.state.status" 'Verbindung unterbrochen...' } catch {}
        Start-Sleep -Seconds 3
        foreach ($o in @($script:Reader, $script:Writer, $script:TcpClient)) { try { if ($o) { $o.Dispose() } } catch {} }
        $script:Reader = $null; $script:Writer = $null; $script:TcpClient = $null
        Connect-TP
    }
}
