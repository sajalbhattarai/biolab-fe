<#
    MARGIE GUI - one-time setup for Windows.

        powershell -ExecutionPolicy Bypass -File .\setup.ps1

        -Check    only report what is installed and what is missing
        -Yes      say yes to every question (unattended)
        -Distro   use a different WSL distribution (default: Ubuntu)

    Why this exists: MARGIE holds ONE ssh login open for a whole session and
    reuses it for the tunnel and for every command it runs on the cluster.
    That is OpenSSH connection multiplexing (ControlMaster), and Windows'
    own ssh.exe does not implement it. Windows also has no lsof and none of
    the Unix process handling the launcher depends on. So on Windows, MARGIE
    runs inside WSL - Microsoft's own Linux environment for Windows - which
    means Windows runs the SAME launcher as macOS and Linux rather than a
    second, weaker one that would drift out of step with it.

    This script sets that up: it checks first, reports what it found, and
    asks before installing anything.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Yes,
    [string]$Distro = 'Ubuntu'
)

# wsl.exe and git write ordinary progress to stderr. Under 'Stop' that becomes
# a thrown exception in the middle of an install that is actually working, so
# exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$MinBuild = 19041          # Windows 10 2004 - the first build with WSL 2
$RepoWin  = $PSScriptRoot
if (-not $RepoWin) { $RepoWin = (Get-Location).Path }   # pasted into a console

# ---------------------------------------------------------------------------
# Output helpers - deliberately the same shape as setup.sh and margie.sh
# ---------------------------------------------------------------------------
function Write-Line    { Write-Host ('  ' + ('-' * 56)) }
function Write-Section { param([string]$Title) Write-Host ''; Write-Line; Write-Host "  $Title"; Write-Line }
function Write-Row     { param([string]$Label, [string]$Value) Write-Host ('  {0,-20} {1}' -f $Label, $Value) }
function Write-Report  { param([string]$Name, [string]$Verdict, [string]$Detail = '') Write-Host ('  {0,-12} {1,-9} {2}' -f $Name, $Verdict, $Detail) }

function Confirm-Step {
    param([string]$Question, [bool]$Default = $true)
    if ($Yes) { return $true }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = Read-Host ("  $Question $hint")
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -match '^\s*(y|yes)\s*$') { return $true }
        if ($answer -match '^\s*(n|no)\s*$')  { return $false }
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Talking to wsl.exe
#
# Older wsl.exe answers in UTF-16 no matter what the console is set to, which
# arrives in PowerShell as text with a NUL after every character - so a plain
# -eq 'Ubuntu' never matches and the distro looks missing. WSL_UTF8 fixes it on
# new builds; stripping the NULs covers the old ones.
# ---------------------------------------------------------------------------
function Invoke-WslCapture {
    param([string[]]$Arguments)
    $env:WSL_UTF8 = '1'
    $previous = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $raw  = & wsl.exe @Arguments 2>&1
    $code = $LASTEXITCODE
    try { [Console]::OutputEncoding = $previous } catch { }
    [pscustomobject]@{
        Text     = ((($raw | Out-String) -replace "`0", '')).Trim()
        ExitCode = $code
    }
}

# Anything that might prompt (first-run user creation, sudo, npm) is run
# WITHOUT capturing, so the prompt is actually visible to the person sitting
# there rather than swallowed into a variable.
function Invoke-WslConsole {
    param([string[]]$Arguments)
    $env:WSL_UTF8 = '1'
    & wsl.exe @Arguments
    return $LASTEXITCODE
}

function Get-WslState {
    $state = [pscustomobject]@{
        Present      = $false
        Enabled      = $false
        StoreVersion = $null
        Distros      = @()
        Target       = $null
    }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $state }
    $state.Present = $true

    $status = Invoke-WslCapture @('--status')
    $state.Enabled = ($status.ExitCode -eq 0)
    if (-not $state.Enabled) { return $state }

    $version = Invoke-WslCapture @('--version')
    if ($version.ExitCode -eq 0 -and $version.Text -match '(\d+\.\d+\.\d+)') {
        $state.StoreVersion = $Matches[1]
    }

    $list = Invoke-WslCapture @('--list', '--quiet')
    if ($list.ExitCode -eq 0) {
        # docker-desktop* are Docker's own plumbing, not distributions anyone
        # can log in to, so they must never be picked as the target.
        $state.Distros = @(
            $list.Text -split "`r?`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notlike 'docker-desktop*' }
        )
    }

    # "Ubuntu" and "Ubuntu-24.04" are both Ubuntu as far as MARGIE cares.
    $exact = $state.Distros | Where-Object { $_ -eq $Distro } | Select-Object -First 1
    if ($exact) { $state.Target = $exact }
    else {
        $state.Target = $state.Distros | Where-Object { $_ -like "$Distro*" } | Select-Object -First 1
    }
    return $state
}

function Get-DistroLocation {
    param([string]$Name)
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $root)) { return $null }
    foreach ($key in Get-ChildItem $root -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
        if ($props.DistributionName -eq $Name) {
            $path = $props.BasePath
            # Stored as an extended-length path (\\?\C:\Users\...), which is
            # correct for the API and unreadable for a person. -like is no use
            # here: ? and * in the prefix are themselves wildcards.
            if ($path -and $path.StartsWith('\\?\')) { $path = $path.Substring(4) }
            return $path
        }
    }
    return $null
}

function ConvertTo-WslPath {
    param([string]$WindowsPath, [string]$InDistro)
    # A repo opened from inside WSL comes through as \\wsl.localhost\Ubuntu\...
    # which has no /mnt mapping at all; translate it straight back.
    if ($WindowsPath -match '^\\\\wsl(\$|\.localhost)\\[^\\]+\\(.*)$') {
        return '/' + ($Matches[2] -replace '\\', '/')
    }
    $result = Invoke-WslCapture @('-d', $InDistro, '--', 'wslpath', '-a', $WindowsPath)
    if ($result.ExitCode -eq 0 -and $result.Text) { return ($result.Text -split "`r?`n")[0].Trim() }
    return $null
}

function Restart-Elevated {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Yes)                 { $arguments += '-Yes' }
    if ($Check)               { $arguments += '-Check' }
    if ($Distro -ne 'Ubuntu') { $arguments += @('-Distro', $Distro) }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# 1. What is already here?
# ---------------------------------------------------------------------------
Write-Section 'MARGIE - setup for Windows'
Write-Row 'MARGIE folder' $RepoWin

$build   = [Environment]::OSVersion.Version.Build
$isAdmin = Test-Admin
$state   = Get-WslState

Write-Section 'Checking this computer'

if ($build -ge $MinBuild) {
    Write-Report 'Windows' 'ok' "build $build"
} else {
    Write-Report 'Windows' 'TOO OLD' "build $build - WSL 2 needs $MinBuild or newer"
}

Write-Report 'admin' $(if ($isAdmin) { 'yes' } else { 'no' }) `
    $(if ($isAdmin) { 'can install Windows features' } else { 'only needed if WSL has to be installed' })

# Reported, never used as a gate: this property is False on machines where
# Hyper-V has already claimed the hypervisor, i.e. exactly where WSL works.
$virt = $null
try { $virt = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).VirtualizationFirmwareEnabled } catch { }
if ($virt -eq $true)       { Write-Report 'virtualisation' 'on' '' }
elseif ($virt -eq $false)  { Write-Report 'virtualisation' 'unclear' 'may need enabling in the BIOS if WSL fails' }
else                       { Write-Report 'virtualisation' 'unknown' '' }

if (-not $state.Present)      { Write-Report 'WSL' 'MISSING' 'Windows Subsystem for Linux is not installed' }
elseif (-not $state.Enabled)  { Write-Report 'WSL' 'MISSING' 'the wsl command is there, but the feature is off' }
else {
    Write-Report 'WSL' 'ok' $(if ($state.StoreVersion) { "version $($state.StoreVersion)" } else { 'built into Windows' })
}

if ($state.Enabled) {
    if ($state.Target) {
        $where  = Get-DistroLocation $state.Target
        $detail = $state.Target
        if ($where) { $detail = $detail + '   installed at ' + $where }
        Write-Report 'Linux' 'ok' $detail
    } elseif ($state.Distros.Count -gt 0) {
        Write-Report 'Linux' 'other' ("no $Distro, but found: " + ($state.Distros -join ', '))
    } else {
        Write-Report 'Linux' 'MISSING' "no Linux distribution installed yet"
    }
}

if ($build -lt $MinBuild) {
    Write-Section 'This version of Windows cannot run MARGIE locally'
    Write-Host '  WSL 2 needs Windows 10 build 19041 (version 2004) or newer.'
    Write-Host '  Update Windows, or just use the hosted app - it needs nothing installed:'
    Write-Host '    https://bsp.anvilcloud.rcac.purdue.edu/'
    exit 1
}

# ---------------------------------------------------------------------------
# 2. -Check: also report the Linux side, then stop without changing anything
# ---------------------------------------------------------------------------
if ($Check) {
    if ($state.Target) {
        $repoLinux = ConvertTo-WslPath -WindowsPath $RepoWin -InDistro $state.Target
        if ($repoLinux) {
            # -lc so a Node installed per-user by nvm, which only exists in the
            # login profile, is seen here exactly as MARGIE will see it.
            Invoke-WslConsole @('-d', $state.Target, '--', 'bash', '-lc',
                "bash '$repoLinux/margie-fe/scripts/check-deps.sh' --check") | Out-Null
        }
    } else {
        Write-Host ''
        Write-Host '  Linux is not set up yet, so the tools MARGIE needs there cannot be checked.'
        Write-Host '  Run setup.ps1 without -Check to install them.'
    }
    Write-Section 'Checked only - nothing was changed'
    exit 0
}

# ---------------------------------------------------------------------------
# 3. Install WSL, if it is not there
# ---------------------------------------------------------------------------
if (-not $state.Enabled) {
    Write-Section 'Windows Subsystem for Linux (WSL) is needed'
    Write-Host '  MARGIE keeps a single SSH login open for your whole session and reuses'
    Write-Host "  it for everything. Windows' own ssh.exe cannot do that, so on Windows"
    Write-Host '  MARGIE runs inside WSL, which is a Microsoft feature of Windows itself.'
    Write-Host ''
    Write-Host '  It installs a small Ubuntu Linux next to Windows. It is NOT a second'
    Write-Host '  operating system to boot into, it does not repartition your disk, and'
    Write-Host '  your Windows files stay exactly where they are.'
    Write-Host ''
    Write-Row 'installs to'  "$env:LOCALAPPDATA\WSL  (older builds: $env:LOCALAPPDATA\Packages)"
    Write-Row 'disk space'   'about 1-2 GB to start with, growing as you use it'
    Write-Row 'needs'        'administrator rights, and one restart of Windows'
    Write-Row 'to remove it' "wsl --unregister $Distro   (takes it away completely)"
    Write-Host ''

    if (-not (Confirm-Step 'Install WSL now?' $true)) {
        Write-Section 'Nothing was installed'
        Write-Host '  You can still use MARGIE with nothing installed at all, in your browser:'
        Write-Host '    https://bsp.anvilcloud.rcac.purdue.edu/'
        exit 0
    }

    if (-not $isAdmin) {
        Write-Host ''
        Write-Host '  Installing a Windows feature needs administrator rights.'
        if (Confirm-Step 'Reopen this setup as administrator?' $true) {
            if (Restart-Elevated) {
                Write-Host '  Continue in the new window that just opened.'
                exit 0
            }
        }
        Write-Host ''
        Write-Host '  Right-click PowerShell, choose "Run as administrator", then run:'
        Write-Host "    powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit 1
    }

    Write-Section 'Installing WSL'

    # --no-distribution keeps the two steps apart, so a failure here is clearly
    # about the Windows feature and not about Ubuntu. It is a newer flag, so
    # older systems fall through to the plain form and then to DISM.
    $installed = (Invoke-WslConsole @('--install', '--no-distribution')) -eq 0
    if (-not $installed) {
        $installed = (Invoke-WslConsole @('--install')) -eq 0
    }

    if (-not $installed) {
        Write-Host '  Falling back to enabling the Windows features directly.'
        & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
        & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
        Write-Host ''
        Write-Host '  You will also need the WSL 2 kernel update once, from:'
        Write-Host '    https://aka.ms/wsl2kernel'
    }

    Write-Section 'Restart Windows, then run this again'
    Write-Host '  WSL is installed but cannot start until Windows restarts.'
    Write-Host '  After restarting, run exactly the same command as before:'
    Write-Host ''
    Write-Host "    powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Write-Host ''
    Write-Host '  It will pick up from here - everything already done is detected and skipped.'
    exit 0
}

# WSL 1 cannot run this stack properly; make 2 the default for new installs.
Invoke-WslCapture @('--set-default-version', '2') | Out-Null

# ---------------------------------------------------------------------------
# 4. Install the Linux distribution, if there is none
# ---------------------------------------------------------------------------
if (-not $state.Target) {
    Write-Section "Linux ($Distro) is needed"

    if ($state.Distros.Count -gt 0) {
        Write-Host "  You already have: $($state.Distros -join ', ')"
        if (Confirm-Step "Use $($state.Distros[0]) instead of installing $Distro?" $true) {
            $state.Target = $state.Distros[0]
        }
    }

    if (-not $state.Target) {
        Write-Host "  About 1-2 GB, installed under $env:LOCALAPPDATA."
        Write-Host '  Ubuntu will ask you to choose a username and password for Linux.'
        Write-Host '  They are only for this Linux and are not your Windows or HPC login.'
        Write-Host ''
        if (-not (Confirm-Step "Install $Distro now?" $true)) {
            Write-Section 'Nothing else was installed'
            Write-Host '  MARGIE also runs in your browser with nothing installed:'
            Write-Host '    https://bsp.anvilcloud.rcac.purdue.edu/'
            exit 0
        }

        Write-Section "Installing $Distro"
        Invoke-WslConsole @('--install', '-d', $Distro) | Out-Null

        $state = Get-WslState
        if (-not $state.Target) {
            Write-Section "Could not install $Distro"
            Write-Host '  Try it by hand, finish the username/password it asks for, then re-run this:'
            Write-Host "    wsl --install -d $Distro"
            exit 1
        }
    }
}

$target = $state.Target
Write-Row 'using' $target

# First contact is uncaptured on purpose: if the distribution has never been
# opened, this is where it asks for the Linux username and password, and that
# question has to reach the screen instead of disappearing into a variable.
if ((Invoke-WslConsole @('-d', $target, '--', 'true')) -ne 0) {
    Write-Section "$target is installed but will not start"
    Write-Host "  Open it once from the Start menu (search for $target), finish its setup,"
    Write-Host '  then run this script again.'
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Put MARGIE on the Linux disk
# ---------------------------------------------------------------------------
Write-Section 'Putting MARGIE where Linux can work with it'

$repoLinux = ConvertTo-WslPath -WindowsPath $RepoWin -InDistro $target
if (-not $repoLinux) {
    Write-Host "  Could not work out where $RepoWin appears inside Linux."
    exit 1
}

$bootstrap = "$repoLinux/margie-fe/scripts/wsl-bootstrap.sh"
$place     = Invoke-WslCapture @('-d', $target, '--', 'bash', $bootstrap, 'place', $repoLinux)

$repoInLinux = $null
foreach ($lineOut in ($place.Text -split "`r?`n")) {
    if ($lineOut -match '^MARGIE_REPO=(.+)$') { $repoInLinux = $Matches[1].Trim() }
    elseif ($lineOut.Trim()) { Write-Host $lineOut }
}
if (-not $repoInLinux) {
    Write-Host '  Could not copy MARGIE into Linux. The lines above say why.'
    exit 1
}
Write-Row 'MARGIE in Linux' $repoInLinux

# ---------------------------------------------------------------------------
# 6. Your SSH key
# ---------------------------------------------------------------------------
$winSsh = Join-Path $env:USERPROFILE '.ssh'
if (Test-Path $winSsh) {
    Write-Section 'Your SSH key'
    Write-Host '  Linux has its own home directory, so the key Windows uses for the cluster'
    Write-Host '  is invisible to MARGIE until it is copied across.'
    Write-Host ''
    Write-Row 'from' $winSsh
    Write-Row 'to'   ($target + ' : ~/.ssh   (keys and known_hosts only)')
    Write-Host ''
    Write-Host '  Nothing already in Linux is overwritten, and nothing leaves this computer.'
    Write-Host ''
    if (Confirm-Step 'Copy your SSH key into Linux?' $true) {
        $winSshLinux = ConvertTo-WslPath -WindowsPath $winSsh -InDistro $target
        if ($winSshLinux) {
            Invoke-WslConsole @('-d', $target, '--', 'bash', $bootstrap, 'ssh-import', $winSshLinux) | Out-Null
        }
    } else {
        Write-Host '  Skipped. MARGIE will show you how to make a key when you register.'
    }
}

# ---------------------------------------------------------------------------
# 7. The 'margie' command on the Windows side
#
# Installed BEFORE setup.sh runs, because setup.sh hands straight over to
# MARGIE itself and would never come back here to finish this.
# ---------------------------------------------------------------------------
Write-Section 'Making "margie" work from Windows'

$binDir  = Join-Path $env:LOCALAPPDATA 'Programs\margie'
$cmdPath = Join-Path $binDir 'margie.cmd'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# Written as ASCII: cmd.exe reads .cmd files in the machine's OEM codepage, and
# anything else turns into mojibake on a non-English Windows.
$launcher = @"
@echo off
rem MARGIE - Windows launcher. The real thing runs inside WSL.
rem Change the distribution below if you ever move MARGIE to another one.
wsl.exe -d $target -- bash -lc "cd ~ && ~/bin/margie %*"
"@
Set-Content -Path $cmdPath -Value $launcher -Encoding ASCII
Write-Row 'installed' $cmdPath

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
# Split and compare exactly rather than -like "*$binDir*": a username with a
# bracket in it turns the pattern into a character class and matches nothing.
if ($userPath.Split(';') -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $binDir).TrimStart(';'), 'User')
    Write-Row 'added to PATH' 'yes - new terminals will find it'
} else {
    Write-Row 'added to PATH' 'already there'
}
$env:Path = $env:Path.TrimEnd(';') + ';' + $binDir

try {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut(
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'MARGIE.lnk'))
    $shortcut.TargetPath   = (Join-Path $env:SystemRoot 'System32\cmd.exe')
    # /k keeps the window open, so a failure is readable instead of a window
    # that blinks once and vanishes.
    $shortcut.Arguments    = "/k `"$cmdPath`""
    $shortcut.Description  = 'Start the MARGIE genome-annotation GUI'
    $shortcut.Save()
    Write-Row 'Start menu' 'MARGIE'
} catch {
    Write-Row 'Start menu' 'could not add a shortcut (the margie command still works)'
}

# ---------------------------------------------------------------------------
# 8. Hand over to the Linux setup: dependencies, then the HPC questions
# ---------------------------------------------------------------------------
Write-Section 'Setting up MARGIE inside Linux'
Write-Host '  Next it checks for Node.js, git, ssh and the rest, asks before installing'
Write-Host '  anything missing, and then asks three questions about your cluster.'
Write-Host ''

# One command, not a try-then-retry: a retry cannot tell "wsl did not understand
# a flag" from "setup.sh failed", and would run the whole HPC questionnaire a
# second time. `bash -lc` needs no flags newer than WSL 1 and cds for itself.
$inner = "cd '$repoInLinux' && bash ./setup.sh --no-launch"
if ($Yes) { $inner += ' --yes' }
$code = Invoke-WslConsole @('-d', $target, '--', 'bash', '-lc', $inner)

if ($code -ne 0) {
    Write-Section 'Setup did not finish'
    Write-Host '  The Linux side stopped with an error - the lines above say why.'
    Write-Host '  Fix it and run this script again; everything already done is skipped.'
    exit 1
}

# ---------------------------------------------------------------------------
# 9. Done
#
# Confirm the launcher setup.sh was supposed to write is really there, rather
# than taking a 0 exit code as proof. "READY" has to mean it.
# ---------------------------------------------------------------------------
# No double quotes in the bash string: PowerShell 5.1 mangles them on the way
# to a native command. A WSL home path has no spaces, so none are needed.
$check = Invoke-WslCapture @('-d', $target, '--', 'bash', '-lc', 'test -x $HOME/bin/margie')
if ($check.ExitCode -ne 0) {
    Write-Section 'Almost - but the margie command was not created'
    Write-Host '  The Linux setup reported success, but ~/bin/margie is missing.'
    Write-Host '  Run it directly to see what happened:'
    Write-Host "    wsl -d $target -- bash -lc `"cd '$repoInLinux' && ./setup.sh`""
    exit 1
}

Write-Section 'MARGIE IS READY'
Write-Row 'run it with'  'margie          (in any new terminal)'
Write-Row 'or'           'Start menu -> MARGIE'
Write-Row 'MARGIE lives' "$target : $repoInLinux"
Write-Row 're-check'     "powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Check"
Write-Host ''

if (Confirm-Step 'Start MARGIE now, so you can register?' $true) {
    & $cmdPath
}
