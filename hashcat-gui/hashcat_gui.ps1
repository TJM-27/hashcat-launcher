Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Get-AppRoot {
    # A compiled exe has no script path. Use the .ps1 folder when that is
    # how the app was started, and the exe folder when it was double-clicked.
    $cmdPath = $null
    if (Test-Path -Path 'variable:PSCommandPath') {
        $cmdPath = $PSCommandPath
    }
    if ($cmdPath -and ([System.IO.Path]::GetExtension($cmdPath) -eq '.ps1')) {
        return (Split-Path -Parent $cmdPath)
    }

    $proc = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($proc -and ([System.IO.Path]::GetFileName($proc) -notmatch '^(powershell|pwsh)(\.exe)?$')) {
        return (Split-Path -Parent $proc)
    }

    $arg0 = [Environment]::GetCommandLineArgs()[0]
    if ($arg0) {
        return (Split-Path -Parent ([System.IO.Path]::GetFullPath($arg0)))
    }
    return (Get-Location).Path
}

function Get-DefaultHashcatPath {
    $scriptDir = Get-AppRoot
    $candidates = @(
        (Join-Path $scriptDir "hashcat-6.2.5\hashcat.exe"),
        (Join-Path $scriptDir "hashcat.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $candidates[0]
}

function Parse-ModeValue([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    return $value.Trim().Split(" ")[0]
}

function Get-MaskCustomSets([string]$mask) {
    $used = @{}
    $dangling = $false
    for ($i = 0; $i -lt $mask.Length; $i++) {
        if ($mask[$i] -ne '?') { continue }
        if ($i + 1 -ge $mask.Length) {
            $dangling = $true
            break
        }
        $token = [string]$mask[$i + 1]
        if ($token -match '^[1-4]$') { $used[$token] = $true }
        $i++
    }
    return [pscustomobject]@{ Dangling = $dangling; Used = $used }
}

function Get-AttackArgumentList {
    param(
        [string]$Attack,
        [string]$Mode,
        [string]$Devices,
        [string]$HashPath,
        [string]$Wordlist,
        [string]$WordlistRight,
        [string]$Mask,
        [string]$Charset1,
        [string]$Charset2,
        [string]$Charset3,
        [string]$Charset4,
        [bool]$Increment,
        [string]$IncrementMin,
        [string]$IncrementMax,
        [string]$RulesPath
    )
    $list = New-Object System.Collections.Generic.List[string]
    $list.Add("-a")
    $list.Add($Attack)
    $list.Add("-m")
    $list.Add($Mode)
    if (-not [string]::IsNullOrWhiteSpace($Devices)) {
        $list.Add("-d")
        $list.Add($Devices)
    }
    if (-not [string]::IsNullOrWhiteSpace($Charset1)) { $list.Add("-1"); $list.Add($Charset1) }
    if (-not [string]::IsNullOrWhiteSpace($Charset2)) { $list.Add("-2"); $list.Add($Charset2) }
    if (-not [string]::IsNullOrWhiteSpace($Charset3)) { $list.Add("-3"); $list.Add($Charset3) }
    if (-not [string]::IsNullOrWhiteSpace($Charset4)) { $list.Add("-4"); $list.Add($Charset4) }
    if ($Increment) {
        $list.Add("-i")
        if (-not [string]::IsNullOrWhiteSpace($IncrementMin)) {
            $list.Add("--increment-min")
            $list.Add($IncrementMin.Trim())
        }
        if (-not [string]::IsNullOrWhiteSpace($IncrementMax)) {
            $list.Add("--increment-max")
            $list.Add($IncrementMax.Trim())
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($RulesPath)) {
        $list.Add("-r")
        $list.Add($RulesPath)
    }
    $list.Add($HashPath)
    switch ($Attack) {
        "1" { $list.Add($Wordlist); $list.Add($WordlistRight) }
        "3" { $list.Add($Mask) }
        "6" { $list.Add($Wordlist); $list.Add($Mask) }
        "7" { $list.Add($Mask); $list.Add($Wordlist) }
        "9" { $list.Add($Wordlist) }
        default { $list.Add($Wordlist) }
    }
    return ,$list.ToArray()
}

function Get-AppIconPath {
    $scriptDir = Get-AppRoot
    $candidates = @(
        (Join-Path $scriptDir "icons\hashcat_gui_cat_icon.ico"),
        (Join-Path $scriptDir "icons\hashcat_gui_cat_icon_legacy.ico"),
        (Join-Path $scriptDir "hashcat_gui_cat_icon.ico")
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }
    return $null
}

$script:CurrentProcess = $null
$script:TempHashPath = $null
$script:HashcatMode = ""
$script:HashcatExe = ""
$script:HashPathForRun = ""
$script:HashcatCwd = ""
$script:RunLogPath = $null
$script:RunErrLogPath = $null
$script:RunLogReadPos = 0
$script:RunErrLogReadPos = 0
$script:AttackLayoutReady = $false

$script:ColorBg = [System.Drawing.Color]::FromArgb(27, 35, 48)
$script:ColorHeader = [System.Drawing.Color]::FromArgb(16, 22, 32)
$script:ColorPanel = [System.Drawing.Color]::FromArgb(36, 47, 64)
$script:ColorText = [System.Drawing.Color]::FromArgb(226, 232, 240)
$script:ColorMuted = [System.Drawing.Color]::FromArgb(154, 168, 188)
$script:ColorAccent = [System.Drawing.Color]::FromArgb(232, 149, 58)
$script:ColorField = [System.Drawing.Color]::FromArgb(244, 247, 251)
$script:ColorInk = [System.Drawing.Color]::FromArgb(26, 35, 51)
$script:ColorRun = [System.Drawing.Color]::FromArgb(22, 145, 112)
$script:ColorRunDim = [System.Drawing.Color]::FromArgb(32, 58, 54)
$script:ColorStop = [System.Drawing.Color]::FromArgb(176, 64, 72)
$script:ColorStopIdle = [System.Drawing.Color]::FromArgb(58, 46, 52)
$script:ColorBrowse = [System.Drawing.Color]::FromArgb(49, 64, 86)
$script:ColorLink = [System.Drawing.Color]::FromArgb(143, 190, 255)
$script:ColorOutput = [System.Drawing.Color]::FromArgb(12, 17, 26)
$script:ColorOutputText = [System.Drawing.Color]::FromArgb(214, 228, 220)

function Set-FlatButton {
    param($Button, $Back, $Fore, [switch]$Bold)
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.UseVisualStyleBackColor = $false
    $Button.BackColor = $Back
    $Button.ForeColor = $Fore
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $style = [System.Drawing.FontStyle]::Regular
    if ($Bold) { $style = [System.Drawing.FontStyle]::Bold }
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 9, $style)
    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Min(255, $Back.R + 18),
        [Math]::Min(255, $Back.G + 18),
        [Math]::Min(255, $Back.B + 18))
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [Math]::Max(0, $Back.R - 18),
        [Math]::Max(0, $Back.G - 18),
        [Math]::Max(0, $Back.B - 18))
}

function Set-FieldBox {
    param($Box)
    $Box.BackColor = $script:ColorField
    $Box.ForeColor = $script:ColorInk
    $Box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Hashcat launcher"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(980, 980)
$form.MinimumSize = New-Object System.Drawing.Size(940, 860)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.BackColor = $script:ColorBg
$form.ForeColor = $script:ColorText
try {
    $iconPath = Get-AppIconPath
    if ($iconPath) {
        $script:FormIcon = New-Object System.Drawing.Icon($iconPath)
        $form.Icon = $script:FormIcon
    }
} catch {
    # Fall back to default icon if the file is missing or unreadable.
}

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(964, 76)
$header.BackColor = $script:ColorHeader
$form.Controls.Add($header)

$accentBar = New-Object System.Windows.Forms.Panel
$accentBar.Height = 3
$accentBar.Dock = "Bottom"
$accentBar.BackColor = $script:ColorAccent
$header.Controls.Add($accentBar)

$picIcon = New-Object System.Windows.Forms.PictureBox
$picIcon.Location = New-Object System.Drawing.Point(14, 12)
$picIcon.Size = New-Object System.Drawing.Size(52, 52)
$picIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picIcon.BackColor = $script:ColorHeader
$headerImagePath = Join-Path (Get-AppRoot) "icons\hashcat_gui_cat_icon_header.png"
if (Test-Path -LiteralPath $headerImagePath) {
    $script:HeaderImage = [System.Drawing.Image]::FromFile($headerImagePath)
    $picIcon.Image = $script:HeaderImage
}
$header.Controls.Add($picIcon)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Hashcat launcher"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.BackColor = $script:ColorHeader
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(76, 12)
$header.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = "Paste hashes or load a file, then choose an attack."
$lblSubtitle.ForeColor = $script:ColorMuted
$lblSubtitle.BackColor = $script:ColorHeader
$lblSubtitle.AutoSize = $true
$lblSubtitle.Location = New-Object System.Drawing.Point(78, 42)
$header.Controls.Add($lblSubtitle)

$form.Add_Resize({
    $header.Width = $form.ClientSize.Width
    if ($script:AttackLayoutReady) { Sync-AttackWidgets }
})

$groupInput = New-Object System.Windows.Forms.GroupBox
$groupInput.Text = "Hash input source"
$groupInput.Location = New-Object System.Drawing.Point(12, 90)
$groupInput.Size = New-Object System.Drawing.Size(948, 96)
$groupInput.BackColor = $script:ColorPanel
$groupInput.ForeColor = $script:ColorAccent
$form.Controls.Add($groupInput)

$rbPaste = New-Object System.Windows.Forms.RadioButton
$rbPaste.Text = "Paste hash(es) in the box below"
$rbPaste.Location = New-Object System.Drawing.Point(14, 26)
$rbPaste.AutoSize = $true
$rbPaste.Checked = $true
$rbPaste.ForeColor = $script:ColorText
$rbPaste.BackColor = $script:ColorPanel
$rbPaste.UseVisualStyleBackColor = $false
$groupInput.Controls.Add($rbPaste)

$rbFile = New-Object System.Windows.Forms.RadioButton
$rbFile.Text = "Load hash(es) from file"
$rbFile.Location = New-Object System.Drawing.Point(280, 26)
$rbFile.AutoSize = $true
$rbFile.ForeColor = $script:ColorText
$rbFile.BackColor = $script:ColorPanel
$rbFile.UseVisualStyleBackColor = $false
$groupInput.Controls.Add($rbFile)

$lblHashFile = New-Object System.Windows.Forms.Label
$lblHashFile.Text = "Hash file:"
$lblHashFile.Location = New-Object System.Drawing.Point(14, 58)
$lblHashFile.AutoSize = $true
$lblHashFile.ForeColor = $script:ColorText
$lblHashFile.BackColor = $script:ColorPanel
$groupInput.Controls.Add($lblHashFile)

$txtHashFile = New-Object System.Windows.Forms.TextBox
$txtHashFile.Location = New-Object System.Drawing.Point(82, 55)
$txtHashFile.Size = New-Object System.Drawing.Size(748, 24)
$txtHashFile.Enabled = $false
Set-FieldBox $txtHashFile
$groupInput.Controls.Add($txtHashFile)

$btnHashBrowse = New-Object System.Windows.Forms.Button
$btnHashBrowse.Text = "Browse..."
$btnHashBrowse.Location = New-Object System.Drawing.Point(838, 53)
$btnHashBrowse.Size = New-Object System.Drawing.Size(94, 28)
$btnHashBrowse.Enabled = $false
Set-FlatButton $btnHashBrowse $script:ColorBrowse $script:ColorText
$groupInput.Controls.Add($btnHashBrowse)

$lblHashes = New-Object System.Windows.Forms.Label
$lblHashes.Text = "Hash(es) - one per line (when Paste is selected):"
$lblHashes.Location = New-Object System.Drawing.Point(14, 196)
$lblHashes.AutoSize = $true
$lblHashes.ForeColor = $script:ColorText
$lblHashes.BackColor = $script:ColorBg
$form.Controls.Add($lblHashes)

$txtHashes = New-Object System.Windows.Forms.TextBox
$txtHashes.Location = New-Object System.Drawing.Point(14, 216)
$txtHashes.Size = New-Object System.Drawing.Size(946, 100)
$txtHashes.Multiline = $true
$txtHashes.ScrollBars = "Vertical"
$txtHashes.AcceptsReturn = $true
$txtHashes.AcceptsTab = $true
$txtHashes.Font = New-Object System.Drawing.Font("Consolas", 10)
Set-FieldBox $txtHashes
$form.Controls.Add($txtHashes)

$lblWordlist = New-Object System.Windows.Forms.Label
$lblWordlist.Text = "Wordlist file:"
$lblWordlist.AutoSize = $true
$lblWordlist.ForeColor = $script:ColorText
$lblWordlist.BackColor = $script:ColorBg
$form.Controls.Add($lblWordlist)

$txtWordlist = New-Object System.Windows.Forms.TextBox
$txtWordlist.Size = New-Object System.Drawing.Size(848, 24)
Set-FieldBox $txtWordlist
$form.Controls.Add($txtWordlist)

$btnWordlistBrowse = New-Object System.Windows.Forms.Button
$btnWordlistBrowse.Text = "Browse..."
$btnWordlistBrowse.Size = New-Object System.Drawing.Size(92, 28)
Set-FlatButton $btnWordlistBrowse $script:ColorBrowse $script:ColorText
$form.Controls.Add($btnWordlistBrowse)

$linkMode = New-Object System.Windows.Forms.LinkLabel
$linkMode.Text = "Hash mode (-m):"
$linkMode.Location = New-Object System.Drawing.Point(14, 384)
$linkMode.AutoSize = $true
$linkMode.LinkColor = $script:ColorLink
$linkMode.ActiveLinkColor = $script:ColorAccent
$linkMode.VisitedLinkColor = $script:ColorLink
$linkMode.LinkBehavior = "HoverUnderline"
$linkMode.BackColor = $script:ColorBg
$form.Controls.Add($linkMode)

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = New-Object System.Drawing.Point(128, 381)
$cmbMode.Size = New-Object System.Drawing.Size(280, 24)
$cmbMode.DropDownStyle = "DropDown"
$cmbMode.FlatStyle = "Flat"
$cmbMode.BackColor = $script:ColorField
$cmbMode.ForeColor = $script:ColorInk
[void]$cmbMode.Items.AddRange(@(
    "5600 (NetNTLMv2)",
    "1000 (NTLM)",
    "0 (MD5)",
    "100 (SHA1)",
    "1400 (SHA2-256)",
    "1700 (SHA2-512)",
    "22000 (WPA-PBKDF2-PMKID+EAPOL)",
    "12500 (RAR3-hp)",
    "13000 (RAR5)"
))
$cmbMode.Text = "5600 (NetNTLMv2)"
$form.Controls.Add($cmbMode)

$linkAttack = New-Object System.Windows.Forms.LinkLabel
$linkAttack.Text = "Attack (-a):"
$linkAttack.AutoSize = $true
$linkAttack.LinkColor = $script:ColorLink
$linkAttack.ActiveLinkColor = $script:ColorAccent
$linkAttack.VisitedLinkColor = $script:ColorLink
$linkAttack.LinkBehavior = "HoverUnderline"
$linkAttack.BackColor = $script:ColorBg
$form.Controls.Add($linkAttack)

$cmbAttack = New-Object System.Windows.Forms.ComboBox
$cmbAttack.Size = New-Object System.Drawing.Size(280, 24)
$cmbAttack.DropDownStyle = "DropDownList"
$cmbAttack.FlatStyle = "Flat"
$cmbAttack.BackColor = $script:ColorField
$cmbAttack.ForeColor = $script:ColorInk
[void]$cmbAttack.Items.AddRange(@(
    "0 (Straight wordlist)",
    "1 (Combination)",
    "3 (Brute-force)",
    "6 (Hybrid wordlist + mask)",
    "7 (Hybrid mask + wordlist)",
    "9 (Association)"
))
$cmbAttack.SelectedIndex = 0
$form.Controls.Add($cmbAttack)

$lblAttackHelp = New-Object System.Windows.Forms.Label
$lblAttackHelp.AutoSize = $true
$lblAttackHelp.ForeColor = $script:ColorMuted
$lblAttackHelp.BackColor = $script:ColorBg
$form.Controls.Add($lblAttackHelp)

$lblWordlist2 = New-Object System.Windows.Forms.Label
$lblWordlist2.Text = "Right wordlist:"
$lblWordlist2.AutoSize = $true
$lblWordlist2.ForeColor = $script:ColorText
$lblWordlist2.BackColor = $script:ColorBg
$form.Controls.Add($lblWordlist2)

$txtWordlist2 = New-Object System.Windows.Forms.TextBox
$txtWordlist2.Size = New-Object System.Drawing.Size(848, 24)
Set-FieldBox $txtWordlist2
$form.Controls.Add($txtWordlist2)

$btnWordlist2Browse = New-Object System.Windows.Forms.Button
$btnWordlist2Browse.Text = "Browse..."
$btnWordlist2Browse.Size = New-Object System.Drawing.Size(92, 28)
Set-FlatButton $btnWordlist2Browse $script:ColorBrowse $script:ColorText
$form.Controls.Add($btnWordlist2Browse)

$lblMask = New-Object System.Windows.Forms.Label
$lblMask.Text = "Mask (example ?a?a?a?a?a?a, or a .hcmask file):"
$lblMask.AutoSize = $true
$lblMask.ForeColor = $script:ColorText
$lblMask.BackColor = $script:ColorBg
$form.Controls.Add($lblMask)

$txtMask = New-Object System.Windows.Forms.TextBox
$txtMask.Size = New-Object System.Drawing.Size(946, 24)
$txtMask.Font = New-Object System.Drawing.Font("Consolas", 10)
Set-FieldBox $txtMask
$form.Controls.Add($txtMask)

function New-CharsetLabel([string]$text) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text
    $lbl.AutoSize = $true
    $lbl.ForeColor = $script:ColorText
    $lbl.BackColor = $script:ColorBg
    return $lbl
}

$lblCs1 = New-CharsetLabel "?1"
$lblCs2 = New-CharsetLabel "?2"
$lblCs3 = New-CharsetLabel "?3"
$lblCs4 = New-CharsetLabel "?4"
$txtCs1 = New-Object System.Windows.Forms.TextBox
$txtCs2 = New-Object System.Windows.Forms.TextBox
$txtCs3 = New-Object System.Windows.Forms.TextBox
$txtCs4 = New-Object System.Windows.Forms.TextBox
foreach ($box in @($txtCs1, $txtCs2, $txtCs3, $txtCs4)) {
    $box.Size = New-Object System.Drawing.Size(170, 24)
    $box.Font = New-Object System.Drawing.Font("Consolas", 10)
    Set-FieldBox $box
}
foreach ($control in @($lblCs1, $txtCs1, $lblCs2, $txtCs2, $lblCs3, $txtCs3, $lblCs4, $txtCs4)) {
    $form.Controls.Add($control)
}

$chkIncrement = New-Object System.Windows.Forms.CheckBox
$chkIncrement.Text = "Increment mask length (-i)"
$chkIncrement.AutoSize = $true
$chkIncrement.ForeColor = $script:ColorText
$chkIncrement.BackColor = $script:ColorBg
$chkIncrement.UseVisualStyleBackColor = $false
$form.Controls.Add($chkIncrement)

$lblIncMin = New-CharsetLabel "Min"
$lblIncMax = New-CharsetLabel "Max"
$txtIncMin = New-Object System.Windows.Forms.TextBox
$txtIncMax = New-Object System.Windows.Forms.TextBox
foreach ($box in @($txtIncMin, $txtIncMax)) {
    $box.Size = New-Object System.Drawing.Size(48, 24)
    Set-FieldBox $box
}
foreach ($control in @($lblIncMin, $txtIncMin, $lblIncMax, $txtIncMax)) {
    $form.Controls.Add($control)
}

$lblRules = New-Object System.Windows.Forms.Label
$lblRules.Text = "Rules file (-r), optional:"
$lblRules.AutoSize = $true
$lblRules.ForeColor = $script:ColorText
$lblRules.BackColor = $script:ColorBg
$form.Controls.Add($lblRules)

$txtRules = New-Object System.Windows.Forms.TextBox
$txtRules.Size = New-Object System.Drawing.Size(848, 24)
Set-FieldBox $txtRules
$form.Controls.Add($txtRules)

$btnRulesBrowse = New-Object System.Windows.Forms.Button
$btnRulesBrowse.Text = "Browse..."
$btnRulesBrowse.Size = New-Object System.Drawing.Size(92, 28)
Set-FlatButton $btnRulesBrowse $script:ColorBrowse $script:ColorText
$form.Controls.Add($btnRulesBrowse)

$lblDevices = New-Object System.Windows.Forms.Label
$lblDevices.Text = "Device(s) (-d), optional. Blank uses every device. Numbers come from hashcat -I:"
$lblDevices.AutoSize = $true
$lblDevices.ForeColor = $script:ColorText
$lblDevices.BackColor = $script:ColorBg
$form.Controls.Add($lblDevices)

$txtDevices = New-Object System.Windows.Forms.TextBox
$txtDevices.Size = New-Object System.Drawing.Size(110, 24)
Set-FieldBox $txtDevices
$form.Controls.Add($txtDevices)

$lblExe = New-Object System.Windows.Forms.Label
$lblExe.Text = "Hashcat executable (optional if on PATH):"
$lblExe.AutoSize = $true
$lblExe.ForeColor = $script:ColorText
$lblExe.BackColor = $script:ColorBg
$form.Controls.Add($lblExe)

$txtExe = New-Object System.Windows.Forms.TextBox
$txtExe.Size = New-Object System.Drawing.Size(848, 24)
$txtExe.Text = Get-DefaultHashcatPath
Set-FieldBox $txtExe
$form.Controls.Add($txtExe)

$btnExeBrowse = New-Object System.Windows.Forms.Button
$btnExeBrowse.Text = "Browse..."
$btnExeBrowse.Size = New-Object System.Drawing.Size(92, 28)
Set-FlatButton $btnExeBrowse $script:ColorBrowse $script:ColorText
$form.Controls.Add($btnExeBrowse)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run hashcat"
$btnRun.Size = New-Object System.Drawing.Size(124, 32)
Set-FlatButton $btnRun $script:ColorRun ([System.Drawing.Color]::White) -Bold
$form.Controls.Add($btnRun)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop"
$btnStop.Size = New-Object System.Drawing.Size(88, 32)
$btnStop.Enabled = $false
Set-FlatButton $btnStop $script:ColorStopIdle $script:ColorMuted -Bold
$form.Controls.Add($btnStop)

$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = "Output:"
$lblOutput.AutoSize = $true
$lblOutput.ForeColor = $script:ColorText
$lblOutput.BackColor = $script:ColorBg
$form.Controls.Add($lblOutput)

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Size = New-Object System.Drawing.Size(946, 180)
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.ReadOnly = $true
$txtOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtOutput.BackColor = $script:ColorOutput
$txtOutput.ForeColor = $script:ColorOutputText
$txtOutput.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($txtOutput)

function Append-Output([string]$line) {
    if ($txtOutput.IsDisposed) { return }
    $action = {
        param($textBox, $text)
        $textBox.AppendText($text)
        $textBox.SelectionStart = $textBox.TextLength
        $textBox.ScrollToCaret()
    }
    if ($txtOutput.InvokeRequired) {
        [void]$txtOutput.BeginInvoke($action, @($txtOutput, $line))
    } else {
        & $action $txtOutput $line
    }
}

function Set-RunningState([bool]$running) {
    $btnRun.Enabled = -not $running
    $btnStop.Enabled = $running
    if ($running) {
        $btnRun.BackColor = $script:ColorRunDim
        $btnRun.ForeColor = $script:ColorMuted
        $btnStop.BackColor = $script:ColorStop
        $btnStop.ForeColor = [System.Drawing.Color]::White
    } else {
        $btnRun.BackColor = $script:ColorRun
        $btnRun.ForeColor = [System.Drawing.Color]::White
        $btnStop.BackColor = $script:ColorStopIdle
        $btnStop.ForeColor = $script:ColorMuted
    }
}

function Cleanup-TempHash {
    if ($script:TempHashPath -and (Test-Path -LiteralPath $script:TempHashPath)) {
        Remove-Item -LiteralPath $script:TempHashPath -Force -ErrorAction SilentlyContinue
    }
    $script:TempHashPath = $null
}

function Cleanup-RunLog {
    $script:RunLogReadPos = 0
    $script:RunErrLogReadPos = 0
    if ($script:RunLogPath -and (Test-Path -LiteralPath $script:RunLogPath)) {
        Remove-Item -LiteralPath $script:RunLogPath -Force -ErrorAction SilentlyContinue
    }
    $script:RunLogPath = $null
    if ($script:RunErrLogPath -and (Test-Path -LiteralPath $script:RunErrLogPath)) {
        Remove-Item -LiteralPath $script:RunErrLogPath -Force -ErrorAction SilentlyContinue
    }
    $script:RunErrLogPath = $null
}

function Read-LogFileIncremental {
    param(
        [string]$Path,
        [ref]$ReadPosition
    )

    if (-not $Path) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($ReadPosition.Value -gt $fs.Length) {
                $ReadPosition.Value = 0
            }
            if ($fs.Length -le $ReadPosition.Value) { return }
            [void]$fs.Seek($ReadPosition.Value, [System.IO.SeekOrigin]::Begin)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
            try {
                $newText = $sr.ReadToEnd()
                if (-not [string]::IsNullOrEmpty($newText)) {
                    Append-Output $newText
                }
            } finally {
                $sr.Dispose()
            }
            $ReadPosition.Value = $fs.Position
        } finally {
            $fs.Dispose()
        }
    } catch {
        # Ignore transient file access races while hashcat writes.
    }
}

function Read-RunLogIncremental {
    Read-LogFileIncremental -Path $script:RunLogPath -ReadPosition ([ref]$script:RunLogReadPos)
    Read-LogFileIncremental -Path $script:RunErrLogPath -ReadPosition ([ref]$script:RunErrLogReadPos)
}

function Show-Recovered {
    param(
        [string]$exePath,
        [string]$mode,
        [string]$hashPath,
        [string]$workingDir
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.WorkingDirectory = $workingDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.Arguments = "-m $mode --show `"$hashPath`""

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        [void]$proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        $lines = @($stdout -split "(`r`n|`n|`r)") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($lines.Count -gt 0) {
            Append-Output "`r`nRecovered password(s):`r`n"
            foreach ($line in $lines) {
                Append-Output "$line`r`n"
            }
            Append-Output "`r`n"
        }
    } catch {
        Append-Output "`r`n[show error] $($_.Exception.Message)`r`n"
    }
}

function Sync-HashSourceWidgets {
    $useFile = $rbFile.Checked
    $txtHashFile.Enabled = $useFile
    $btnHashBrowse.Enabled = $useFile
    $txtHashes.Enabled = -not $useFile
}

function Sync-AttackWidgets {
    if (-not $script:AttackLayoutReady) { return }
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }

    $attack = Parse-ModeValue $cmbAttack.Text
    if ($attack -notin @("0", "1", "3", "6", "7", "9")) { $attack = "0" }

    $needsWordlist = $attack -ne "3"
    $needsRight = $attack -eq "1"
    $needsMask = $attack -in @("3", "6", "7")
    $needsRules = $attack -eq "9"

    $lblWordlist.Visible = $needsWordlist
    $txtWordlist.Visible = $needsWordlist
    $btnWordlistBrowse.Visible = $needsWordlist
    if ($attack -eq "1") {
        $lblWordlist.Text = "Left wordlist:"
    } else {
        $lblWordlist.Text = "Wordlist file:"
    }

    $lblAttackHelp.Text = switch ($attack) {
        "0" { "Straight: try each word in the wordlist." }
        "1" { "Combination: join every left word to every right word." }
        "3" { "Brute-force: try every candidate that matches the mask. No wordlist." }
        "6" { "Hybrid: each wordlist word, with the mask added after it." }
        "7" { "Hybrid: the mask, with each wordlist word added after it." }
        "9" { "Association: try the wordlist against the hashes. A rules file is optional." }
        default { "" }
    }

    $y = 326
    if ($needsWordlist) {
        $lblWordlist.Location = New-Object System.Drawing.Point(14, $y)
        $y += 20
        $txtWordlist.Location = New-Object System.Drawing.Point(14, $y)
        $btnWordlistBrowse.Location = New-Object System.Drawing.Point(868, ($y - 2))
        $y += 36
    }

    $linkMode.Location = New-Object System.Drawing.Point(14, ($y + 4))
    $cmbMode.Location = New-Object System.Drawing.Point(128, $y)
    $y += 36

    $linkAttack.Location = New-Object System.Drawing.Point(14, ($y + 4))
    $cmbAttack.Location = New-Object System.Drawing.Point(110, $y)
    $y += 30
    $lblAttackHelp.Location = New-Object System.Drawing.Point(14, $y)
    $y += 26

    foreach ($control in @($lblWordlist2, $txtWordlist2, $btnWordlist2Browse)) { $control.Visible = $needsRight }
    if ($needsRight) {
        $lblWordlist2.Location = New-Object System.Drawing.Point(14, $y)
        $y += 20
        $txtWordlist2.Location = New-Object System.Drawing.Point(14, $y)
        $btnWordlist2Browse.Location = New-Object System.Drawing.Point(868, ($y - 2))
        $y += 36
    }

    foreach ($control in @($lblMask, $txtMask, $lblCs1, $txtCs1, $lblCs2, $txtCs2, $lblCs3, $txtCs3, $lblCs4, $txtCs4, $chkIncrement, $lblIncMin, $txtIncMin, $lblIncMax, $txtIncMax)) {
        $control.Visible = $needsMask
    }
    if ($needsMask) {
        $lblMask.Location = New-Object System.Drawing.Point(14, $y)
        $y += 20
        $txtMask.Location = New-Object System.Drawing.Point(14, $y)
        $y += 34
        $lblCs1.Location = New-Object System.Drawing.Point(14, ($y + 4))
        $txtCs1.Location = New-Object System.Drawing.Point(40, $y)
        $lblCs2.Location = New-Object System.Drawing.Point(224, ($y + 4))
        $txtCs2.Location = New-Object System.Drawing.Point(250, $y)
        $lblCs3.Location = New-Object System.Drawing.Point(434, ($y + 4))
        $txtCs3.Location = New-Object System.Drawing.Point(460, $y)
        $lblCs4.Location = New-Object System.Drawing.Point(644, ($y + 4))
        $txtCs4.Location = New-Object System.Drawing.Point(670, $y)
        $y += 34
        $chkIncrement.Location = New-Object System.Drawing.Point(14, ($y + 3))
        $lblIncMin.Location = New-Object System.Drawing.Point(230, ($y + 4))
        $txtIncMin.Location = New-Object System.Drawing.Point(262, $y)
        $lblIncMax.Location = New-Object System.Drawing.Point(324, ($y + 4))
        $txtIncMax.Location = New-Object System.Drawing.Point(360, $y)
        $incOn = $chkIncrement.Checked
        $txtIncMin.Enabled = $incOn
        $txtIncMax.Enabled = $incOn
        $y += 36
    }

    foreach ($control in @($lblRules, $txtRules, $btnRulesBrowse)) { $control.Visible = $needsRules }
    if ($needsRules) {
        $lblRules.Location = New-Object System.Drawing.Point(14, $y)
        $y += 20
        $txtRules.Location = New-Object System.Drawing.Point(14, $y)
        $btnRulesBrowse.Location = New-Object System.Drawing.Point(868, ($y - 2))
        $y += 36
    }

    $lblDevices.Location = New-Object System.Drawing.Point(14, ($y + 4))
    $txtDevices.Location = New-Object System.Drawing.Point(700, $y)
    $y += 36
    $lblExe.Location = New-Object System.Drawing.Point(14, $y)
    $y += 20
    $txtExe.Location = New-Object System.Drawing.Point(14, $y)
    $btnExeBrowse.Location = New-Object System.Drawing.Point(868, ($y - 2))
    $y += 40
    $btnRun.Location = New-Object System.Drawing.Point(14, $y)
    $btnStop.Location = New-Object System.Drawing.Point(146, $y)
    $y += 42
    $lblOutput.Location = New-Object System.Drawing.Point(14, $y)
    $y += 20
    $txtOutput.Location = New-Object System.Drawing.Point(14, $y)
    $available = $form.ClientSize.Height - $y - 14
    if ($available -lt 80) { $available = 80 }
    $txtOutput.Height = $available
}

$rbPaste.Add_CheckedChanged({ Sync-HashSourceWidgets })
$rbFile.Add_CheckedChanged({ Sync-HashSourceWidgets })

$btnHashBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select hash file"
    $dlg.Filter = "Text/Hash Files|*.txt;*.hash;*.*|All files|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtHashFile.Text = $dlg.FileName
    }
})

$btnWordlistBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select wordlist"
    $dlg.Filter = "Text Files|*.txt;*.*|All files|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtWordlist.Text = $dlg.FileName
    }
})

$btnWordlist2Browse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select right wordlist"
    $dlg.Filter = "Text Files|*.txt;*.*|All files|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtWordlist2.Text = $dlg.FileName
    }
})

$btnRulesBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select rules file"
    $dlg.Filter = "Hashcat rules|*.rule;*.*|All files|*.*"
    $rulesDir = Join-Path (Get-AppRoot) "hashcat-6.2.5\rules"
    if (Test-Path -LiteralPath $rulesDir) { $dlg.InitialDirectory = $rulesDir }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtRules.Text = $dlg.FileName
    }
})

$cmbAttack.Add_SelectedIndexChanged({ Sync-AttackWidgets })
$chkIncrement.Add_CheckedChanged({ Sync-AttackWidgets })

$btnExeBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select hashcat executable"
    $dlg.Filter = "Executable|*.exe|All files|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtExe.Text = $dlg.FileName
    }
})

$linkMode.add_LinkClicked({
    Start-Process "https://hashcat.net/wiki/doku.php?id=example_hashes"
})

$linkAttack.add_LinkClicked({
    Start-Process "https://hashcat.net/wiki/"
})

$btnStop.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        try { $script:CurrentProcess.Kill() } catch {}
    }
})

$btnRun.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        [System.Windows.Forms.MessageBox]::Show("Hashcat is already running.", "Busy")
        return
    }

    $hashPath = ""
    $script:TempHashPath = $null

    if ($rbFile.Checked) {
        if ([string]::IsNullOrWhiteSpace($txtHashFile.Text) -or -not (Test-Path -LiteralPath $txtHashFile.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Choose a valid hash file.", "Hash file")
            return
        }
        $hashPath = (Resolve-Path -LiteralPath $txtHashFile.Text).Path
    } else {
        if ([string]::IsNullOrWhiteSpace($txtHashes.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Enter at least one hash, or use a hash file.", "Missing hash")
            return
        }
        $tmp = Join-Path $env:TEMP ("hc_gui_" + [Guid]::NewGuid().ToString("N") + ".txt")
        $lines = @($txtHashes.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        [System.IO.File]::WriteAllLines($tmp, $lines)
        $hashPath = $tmp
        $script:TempHashPath = $tmp
    }

    $mode = Parse-ModeValue $cmbMode.Text
    if ($mode -notmatch '^\d+$') {
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Hash mode (-m) must be a number.", "Mode")
        return
    }

    $attack = Parse-ModeValue $cmbAttack.Text
    if ($attack -notin @("0", "1", "3", "6", "7", "9")) {
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Choose an attack mode.", "Attack")
        return
    }

    $wordlistPath = ""
    $wordlistRight = ""
    $mask = ""
    $rulesPath = ""

    if ($attack -ne "3") {
        if ([string]::IsNullOrWhiteSpace($txtWordlist.Text) -or -not (Test-Path -LiteralPath $txtWordlist.Text -PathType Leaf)) {
            Cleanup-TempHash
            [System.Windows.Forms.MessageBox]::Show("Choose a valid wordlist file.", "Wordlist")
            return
        }
        $wordlistPath = (Resolve-Path -LiteralPath $txtWordlist.Text).Path
    }

    if ($attack -eq "1") {
        if ([string]::IsNullOrWhiteSpace($txtWordlist2.Text) -or -not (Test-Path -LiteralPath $txtWordlist2.Text -PathType Leaf)) {
            Cleanup-TempHash
            [System.Windows.Forms.MessageBox]::Show("Choose the right wordlist.", "Wordlist")
            return
        }
        $wordlistRight = (Resolve-Path -LiteralPath $txtWordlist2.Text).Path
    }

    if ($attack -in @("3", "6", "7")) {
        $mask = $txtMask.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($mask)) {
            Cleanup-TempHash
            [System.Windows.Forms.MessageBox]::Show("Enter a mask, for example ?a?a?a?a?a?a, or choose a .hcmask file.", "Mask")
            return
        }
        if (Test-Path -LiteralPath $mask -PathType Leaf) {
            $mask = (Resolve-Path -LiteralPath $mask).Path
        } else {
            $parsedMask = Get-MaskCustomSets $mask
            if ($parsedMask.Dangling) {
                Cleanup-TempHash
                [System.Windows.Forms.MessageBox]::Show("The mask ends with a ?. Put a charset letter or custom set number after it.", "Mask")
                return
            }
            $charsets = @{
                "1" = $txtCs1.Text.Trim()
                "2" = $txtCs2.Text.Trim()
                "3" = $txtCs3.Text.Trim()
                "4" = $txtCs4.Text.Trim()
            }
            foreach ($key in @("1", "2", "3", "4")) {
                if ($parsedMask.Used.ContainsKey($key) -and [string]::IsNullOrWhiteSpace($charsets[$key])) {
                    Cleanup-TempHash
                    [System.Windows.Forms.MessageBox]::Show("This mask uses ?$key. Fill in custom charset ?$key.", "Mask")
                    return
                }
            }
        }
        if ($chkIncrement.Checked) {
            $incMin = $txtIncMin.Text.Trim()
            $incMax = $txtIncMax.Text.Trim()
            if ($incMin -and $incMin -notmatch '^\d+$') {
                Cleanup-TempHash
                [System.Windows.Forms.MessageBox]::Show("Increment minimum must be a number.", "Mask")
                return
            }
            if ($incMax -and $incMax -notmatch '^\d+$') {
                Cleanup-TempHash
                [System.Windows.Forms.MessageBox]::Show("Increment maximum must be a number.", "Mask")
                return
            }
            if ($incMin -and $incMax -and ([int]$incMin -gt [int]$incMax)) {
                Cleanup-TempHash
                [System.Windows.Forms.MessageBox]::Show("Increment minimum cannot be greater than the maximum.", "Mask")
                return
            }
        }
    }

    if ($attack -eq "9" -and -not [string]::IsNullOrWhiteSpace($txtRules.Text)) {
        if (-not (Test-Path -LiteralPath $txtRules.Text -PathType Leaf)) {
            Cleanup-TempHash
            [System.Windows.Forms.MessageBox]::Show("Choose a valid rules file, or leave that box blank.", "Rules")
            return
        }
        $rulesPath = (Resolve-Path -LiteralPath $txtRules.Text).Path
    }

    $devices = $txtDevices.Text.Trim()
    if ($devices -and ($devices -notmatch '^\d+(,\d+)*$')) {
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Device list must be comma-separated numbers (e.g. 1 or 1,3).", "Devices")
        return
    }

    if ([string]::IsNullOrWhiteSpace($txtExe.Text)) {
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Set the path to hashcat or leave default if on PATH.", "Executable")
        return
    }

    $exeInput = $txtExe.Text.Trim()
    $exePath = $exeInput
    if (Test-Path -LiteralPath $exeInput) {
        $exePath = (Resolve-Path -LiteralPath $exeInput).Path
    } else {
        $cmd = Get-Command $exeInput -ErrorAction SilentlyContinue
        if ($cmd) { $exePath = $cmd.Source }
    }

    if (-not (Test-Path -LiteralPath $exePath)) {
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Cannot find hashcat executable: $exeInput", "Executable")
        return
    }

    $workingDir = Split-Path -Parent $exePath
    $incMinArg = ""
    $incMaxArg = ""
    $charset1 = ""
    $charset2 = ""
    $charset3 = ""
    $charset4 = ""
    $useIncrement = $false
    if ($attack -in @("3", "6", "7")) {
        $charset1 = $txtCs1.Text.Trim()
        $charset2 = $txtCs2.Text.Trim()
        $charset3 = $txtCs3.Text.Trim()
        $charset4 = $txtCs4.Text.Trim()
        $useIncrement = $chkIncrement.Checked
        if ($useIncrement) {
            $incMinArg = $txtIncMin.Text.Trim()
            $incMaxArg = $txtIncMax.Text.Trim()
        }
    }
    $argList = Get-AttackArgumentList `
        -Attack $attack `
        -Mode $mode `
        -Devices $devices `
        -HashPath $hashPath `
        -Wordlist $wordlistPath `
        -WordlistRight $wordlistRight `
        -Mask $mask `
        -Charset1 $charset1 `
        -Charset2 $charset2 `
        -Charset3 $charset3 `
        -Charset4 $charset4 `
        -Increment $useIncrement `
        -IncrementMin $incMinArg `
        -IncrementMax $incMaxArg `
        -RulesPath $rulesPath

    $quotedArgs = $argList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $argsText = [string]::Join(" ", $quotedArgs)

    $txtOutput.Clear()
    Append-Output ("Command: `"" + $exePath + "`" " + $argsText + "`r`n")
    Append-Output ("Working directory: " + $workingDir + "`r`n`r`n")

    $script:HashcatMode = $mode
    $script:HashcatExe = $exePath
    $script:HashPathForRun = $hashPath
    $script:HashcatCwd = $workingDir

    try {
        Cleanup-RunLog
        $script:RunLogPath = Join-Path $env:TEMP ("hc_gui_run_" + [Guid]::NewGuid().ToString("N") + ".log")
        $script:RunErrLogPath = Join-Path $env:TEMP ("hc_gui_run_" + [Guid]::NewGuid().ToString("N") + ".err.log")
        $script:RunLogReadPos = 0
        $script:RunErrLogReadPos = 0
        $proc = Start-Process -FilePath $exePath -ArgumentList $argList -WorkingDirectory $workingDir -NoNewWindow -PassThru -RedirectStandardOutput $script:RunLogPath -RedirectStandardError $script:RunErrLogPath
    } catch {
        Cleanup-RunLog
        Cleanup-TempHash
        [System.Windows.Forms.MessageBox]::Show("Failed to start hashcat: $($_.Exception.Message)", "Error")
        return
    }

    $script:CurrentProcess = $proc
    Set-RunningState $true
})

$form.Add_FormClosing({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        try { $script:CurrentProcess.Kill() } catch {}
    }
    Cleanup-RunLog
    Cleanup-TempHash
})

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 200
$pollTimer.Add_Tick({
    Read-RunLogIncremental
    if ($script:CurrentProcess -and $script:CurrentProcess.HasExited) {
        $exitCode = $script:CurrentProcess.ExitCode
        if ($exitCode -eq 0) {
            Show-Recovered -exePath $script:HashcatExe -mode $script:HashcatMode -hashPath $script:HashPathForRun -workingDir $script:HashcatCwd
        }
        Append-Output ("`r`n--- Exit code: " + $exitCode + " ---`r`n")
        $script:CurrentProcess = $null
        Cleanup-RunLog
        Cleanup-TempHash
        Set-RunningState $false
    }
})
$pollTimer.Start()

Sync-HashSourceWidgets
Set-RunningState $false
$script:AttackLayoutReady = $true
Sync-AttackWidgets
[void]$form.ShowDialog()
