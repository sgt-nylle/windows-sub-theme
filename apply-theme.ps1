<#
.SYNOPSIS
    Applies the "Sub Theme (Gotland Navy)" to Windows 11 and Windows Terminal
    without requiring administrator privileges or system file patching.

.DESCRIPTION
    Ported from https://github.com/sgt-nylle/omarchy-sub-theme
    - Enables Windows 11 Dark Mode for both system UI and applications.
    - Sets DWM and Explorer accent colors to the Gotland Navy / Periscope Cyan palette
      (#07162C background, #164682 tactical navy selection, #38BDF8 sonar cyan accent)
      and enables accent color prevalence on title bars, window borders, and taskbar.
    - Applies the selected 2736x1824 Gotland-class Cold War bluedark wallpaper immediately
      via the Win32 user32.dll SystemParametersInfo API (no sign-out required).
    - Detects Windows Terminal (Stable, Preview, or Scoop/Winget unpackaged) and
      injects the 16-color "Sub Theme" ANSI scheme into settings.json (with backup).

.PARAMETER WallpaperIndex
    Selects which of the 4 included Gotland-class wallpapers to set (1 to 4, default: 1):
      1 = 01-stockholm-archipelago-night-patrol.png (Default)
      2 = 02-hms-gotland-tactical-blueprint.png
      3 = 03-baltic-sonar-silent-running.png
      4 = 04-dawn-torpedo-run.png

.PARAMETER WallpaperStyle
    Desktop fit mode: Fill (default), Fit, Center, or Span.

.PARAMETER SetAsDefaultTerminalScheme
    Also sets "Sub Theme" as the active colorScheme under profiles.defaults in Windows Terminal.

.PARAMETER Revert
    Restores Windows 11 default dark/light personalization and DWM accent settings.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -Scope Process -File .\apply-theme.ps1
.EXAMPLE
    .\apply-theme.ps1 -WallpaperIndex 3 -SetAsDefaultTerminalScheme
.EXAMPLE
    .\apply-theme.ps1 -Revert
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 4)]
    [int]$WallpaperIndex = 1,

    [ValidateSet('Fill', 'Fit', 'Center', 'Span')]
    [string]$WallpaperStyle = 'Fill',

    [switch]$SetAsDefaultTerminalScheme,

    [switch]$Revert
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Win32 P/Invoke for Immediate Wallpaper Refresh ──────────────────────────
$Win32WallpaperDef = @"
using System;
using System.Runtime.InteropServices;

namespace SubThemeWin32 {
    public static class NativeMethods {
        public const int SPI_SETDESKWALLPAPER = 0x0014;
        public const int SPIF_UPDATEINIFILE   = 0x01;
        public const int SPIF_SENDWININICHANGE = 0x02;

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SystemParametersInfo(
            int uAction,
            int uParam,
            string lpvParam,
            int fuWinIni
        );
    }
}
"@

if (-not ('SubThemeWin32.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition $Win32WallpaperDef -Language CSharp
}

function Write-Step {
    param([string]$Message)
    Write-Host "[Sub Theme] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Gray
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# ── Rollback / Revert Handler ───────────────────────────────────────────────
if ($Revert) {
    try {
        Write-Step "Reverting Windows 11 Personalize & DWM settings to standard defaults..."
        $PersonalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        Set-RegistryValue -Path $PersonalizePath -Name 'AppsUseLightTheme'   -Value 0
        Set-RegistryValue -Path $PersonalizePath -Name 'SystemUsesLightTheme' -Value 0
        Set-RegistryValue -Path $PersonalizePath -Name 'ColorPrevalence'     -Value 0
        Set-RegistryValue -Path $PersonalizePath -Name 'EnableTransparency'  -Value 1

        $DwmPath = 'HKCU:\Software\Microsoft\Windows\DWM'
        Set-RegistryValue -Path $DwmPath -Name 'ColorPrevalence'  -Value 0
        Set-RegistryValue -Path $DwmPath -Name 'AutoColorization' -Value 0
        if (Get-ItemProperty -LiteralPath $DwmPath -Name 'AccentColorInactive' -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -LiteralPath $DwmPath -Name 'AccentColorInactive' -ErrorAction SilentlyContinue
        }

        $DefaultWall = Join-Path $env:SystemRoot 'Web\Wallpaper\Windows\img19.jpg'
        if (-not (Test-Path -LiteralPath $DefaultWall)) {
            $DefaultWall = Join-Path $env:SystemRoot 'Web\Wallpaper\Windows\img0.jpg'
        }
        if (Test-Path -LiteralPath $DefaultWall) {
            [void][SubThemeWin32.NativeMethods]::SystemParametersInfo(
                [SubThemeWin32.NativeMethods]::SPI_SETDESKWALLPAPER,
                0,
                $DefaultWall,
                ([SubThemeWin32.NativeMethods]::SPIF_UPDATEINIFILE -bor [SubThemeWin32.NativeMethods]::SPIF_SENDWININICHANGE)
            )
        }
        Write-Ok "Windows 11 accent prevalence and default dark wallpaper restored."
        exit 0
    }
    catch {
        Write-Error "Failed to revert theme settings: $($_.Exception.Message)"
        exit 1
    }
}

# ── 1. Enable Windows 11 Dark Mode (System + Apps) ──────────────────────────
try {
    Write-Step "Configuring Windows 11 Dark Mode & Taskbar Accent..."
    $PersonalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    Set-RegistryValue -Path $PersonalizePath -Name 'AppsUseLightTheme'    -Value 0
    Set-RegistryValue -Path $PersonalizePath -Name 'SystemUsesLightTheme' -Value 0
    Set-RegistryValue -Path $PersonalizePath -Name 'EnableTransparency'   -Value 1
    Set-RegistryValue -Path $PersonalizePath -Name 'ColorPrevalence'      -Value 1

    Write-Ok "SystemMode=Dark, AppMode=Dark, EnableTransparency=1, ColorPrevalence=1"
}
catch {
    Write-Error "Failed to configure Personalize registry keys: $($_.Exception.Message)"
    exit 1
}

# ── 2. Set DWM & Explorer Accent Colors (Gotland Navy + Periscope Cyan) ─────
try {
    Write-Step "Applying Gotland Navy & Periscope Cyan DWM Accent Colors..."
    $DwmPath    = 'HKCU:\Software\Microsoft\Windows\DWM'
    $AccentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'

    # Palette extracted from omarchy-sub-theme/colors.toml:
    #   selection / active frame : #164682 (R=0x16, G=0x46, B=0x82)
    #   lighter_background       : #0F2B52 (R=0x0F, G=0x2B, B=0x52)
    #   hairline                 : #1B457D (R=0x1B, G=0x45, B=0x7D)
    #   background               : #07162C (R=0x07, G=0x16, B=0x2C)
    #   accent / cyan            : #38BDF8 (R=0x38, G=0xBD, B=0xF8)
    #
    # Note:
    # - DWM ColorizationColor / ColorizationAfterglow use ARGB (0xAARRGGBB)
    # - DWM AccentColor / AccentColorInactive & Explorer Accent use ABGR (0xAABBGGRR)
    $ColorizationARGB    = [Convert]::ToInt32('C4164682', 16) # ARGB #164682 (Tactical Navy Selection)
    $ActiveAccentABGR    = [Convert]::ToInt32('FF824616', 16) # ABGR #164682 (Active Titlebar / Border)
    $InactiveAccentABGR  = [Convert]::ToInt32('FF2C1607', 16) # ABGR #07162C (Deep Baltic Navy Inactive Titlebar)
    $StartMenuAccentABGR = [Convert]::ToInt32('FF522B0F', 16) # ABGR #0F2B52 (Elevated Navy Card / Taskbar Tint)

    Set-RegistryValue -Path $DwmPath -Name 'AutoColorization'      -Value 0
    Set-RegistryValue -Path $DwmPath -Name 'ColorPrevalence'       -Value 1
    Set-RegistryValue -Path $DwmPath -Name 'ColorizationColor'     -Value $ColorizationARGB
    Set-RegistryValue -Path $DwmPath -Name 'ColorizationAfterglow' -Value $ColorizationARGB
    Set-RegistryValue -Path $DwmPath -Name 'AccentColor'           -Value $ActiveAccentABGR
    Set-RegistryValue -Path $DwmPath -Name 'AccentColorInactive'   -Value $InactiveAccentABGR

    # 8-slot RGBA binary AccentPalette (lightest cyan highlight -> deepest abyssal navy):
    #   Slot 0 (Light3): #A5F3FC  | Slot 1 (Light2): #67E8F9  | Slot 2 (Light1): #38BDF8
    #   Slot 3 (Normal): #164682  | Slot 4 (Dark1) : #1B457D  | Slot 5 (Dark2) : #0F2B52
    #   Slot 6 (Dark3) : #07162C  | Slot 7 (Frame) : #040E1D
    [byte[]]$AccentPaletteBytes = @(
        0xA5, 0xF3, 0xFC, 0xFF,
        0x67, 0xE8, 0xF9, 0xFF,
        0x38, 0xBD, 0xF8, 0xFF,
        0x16, 0x46, 0x82, 0xFF,
        0x1B, 0x45, 0x7D, 0xFF,
        0x0F, 0x2B, 0x52, 0xFF,
        0x07, 0x16, 0x2C, 0xFF,
        0x04, 0x0E, 0x1D, 0xFF
    )
    Set-RegistryValue -Path $AccentPath -Name 'AccentPalette'   -Value $AccentPaletteBytes -Type Binary
    Set-RegistryValue -Path $AccentPath -Name 'AccentColorMenu' -Value $ActiveAccentABGR
    Set-RegistryValue -Path $AccentPath -Name 'StartColorMenu'  -Value $StartMenuAccentABGR

    Write-Ok "DWM AccentColor=#164682, Inactive=#07162C, UI Highlight=#38BDF8 (Periscope Cyan)"
}
catch {
    Write-Error "Failed to configure DWM/Accent registry keys: $($_.Exception.Message)"
    exit 1
}

# ── 3. Set Desktop Wallpaper Immediately via user32.dll ─────────────────────
try {
    $WallpaperFiles = @(
        '01-stockholm-archipelago-night-patrol.png',
        '02-hms-gotland-tactical-blueprint.png',
        '03-baltic-sonar-silent-running.png',
        '04-dawn-torpedo-run.png'
    )
    $SelectedFile = $WallpaperFiles[$WallpaperIndex - 1]
    $WallpaperPath = Join-Path $PSScriptRoot (Join-Path 'backgrounds' $SelectedFile)

    if (-not (Test-Path -LiteralPath $WallpaperPath)) {
        throw "Wallpaper asset not found at: $WallpaperPath"
    }

    Write-Step "Applying wallpaper [$WallpaperIndex/4]: $SelectedFile ($WallpaperStyle)..."

    $DesktopPath = 'HKCU:\Control Panel\Desktop'
    $StyleCode = switch ($WallpaperStyle) {
        'Fill'   { '10' }
        'Fit'    { '6'  }
        'Center' { '0'  }
        'Span'   { '22' }
    }
    Set-RegistryValue -Path $DesktopPath -Name 'WallpaperStyle' -Value $StyleCode -Type String
    Set-RegistryValue -Path $DesktopPath -Name 'TileWallpaper'  -Value '0'        -Type String

    # Set solid background fallback to #07162c (7 22 44)
    $ColorsPath = 'HKCU:\Control Panel\Colors'
    Set-RegistryValue -Path $ColorsPath -Name 'Background' -Value '7 22 44' -Type String

    $Result = [SubThemeWin32.NativeMethods]::SystemParametersInfo(
        [SubThemeWin32.NativeMethods]::SPI_SETDESKWALLPAPER,
        0,
        $WallpaperPath,
        ([SubThemeWin32.NativeMethods]::SPIF_UPDATEINIFILE -bor [SubThemeWin32.NativeMethods]::SPIF_SENDWININICHANGE)
    )
    if ($Result -eq 0) {
        $LastErr = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Warn "SystemParametersInfo returned 0 (Win32 error $LastErr), but registry path was updated."
    }
    else {
        Write-Ok "Desktop wallpaper updated live via SystemParametersInfo."
    }
}
catch {
    Write-Error "Failed to apply desktop wallpaper: $($_.Exception.Message)"
    exit 1
}

# ── 4. Inject "Sub Theme" Color Scheme into Windows Terminal ────────────────
try {
    Write-Step "Checking for Windows Terminal installation..."

    $TerminalCandidatePaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )

    $FoundPaths = @($TerminalCandidatePaths | Where-Object { Test-Path -LiteralPath $_ })

    # Exact 16-slot ANSI + semantic palette from sgt-nylle/omarchy-sub-theme (colors.toml)
    $SubThemeScheme = [ordered]@{
        name                = 'Sub Theme'
        background          = '#07162C'
        foreground          = '#E2EEFF'
        cursorColor         = '#F8FBFF'
        selectionBackground = '#164682'
        black               = '#040E1D'
        red                 = '#FF5C5C'
        green               = '#34D399'
        yellow              = '#FECC02'
        blue                = '#5494F7'
        purple              = '#A78BFA'
        cyan                = '#38BDF8'
        white               = '#E2EEFF'
        brightBlack         = '#5B82B8'
        brightRed           = '#FF8585'
        brightGreen         = '#4ADE80'
        brightYellow        = '#FDE047'
        brightBlue          = '#82B5FF'
        brightPurple        = '#C4B5FD'
        brightCyan          = '#67E8F9'
        brightWhite         = '#F8FBFF'
    }

    if ($FoundPaths.Count -eq 0) {
        Write-Warn "Windows Terminal settings.json not found. Skipping terminal color scheme injection."
    }
    else {
        foreach ($SettingsPath in $FoundPaths) {
            try {
                $BackupPath = "$SettingsPath.subtheme.bak"
                Copy-Item -LiteralPath $SettingsPath -Destination $BackupPath -Force

                $RawJson = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8
                # Strip single-line // comments (outside strings) so Windows PowerShell 5.1 ConvertFrom-Json succeeds
                $CleanJson = [regex]::Replace($RawJson, '(?m)^\s*//.*$', '')
                $SettingsObj = $CleanJson | ConvertFrom-Json

                if (-not ($SettingsObj.PSObject.Properties.Name -contains 'schemes') -or $null -eq $SettingsObj.schemes) {
                    $SettingsObj | Add-Member -MemberType NoteProperty -Name 'schemes' -Value @() -Force
                }

                # Filter out any existing "Sub Theme" entry and append the fresh definition
                $UpdatedSchemes = @($SettingsObj.schemes | Where-Object { $_.name -ne 'Sub Theme' })
                $UpdatedSchemes += [pscustomobject]$SubThemeScheme
                $SettingsObj.schemes = $UpdatedSchemes

                if ($SetAsDefaultTerminalScheme) {
                    if (-not ($SettingsObj.PSObject.Properties.Name -contains 'profiles')) {
                        $SettingsObj | Add-Member -MemberType NoteProperty -Name 'profiles' -Value ([pscustomobject]@{ defaults = [pscustomobject]@{} })
                    }
                    if (-not ($SettingsObj.profiles.PSObject.Properties.Name -contains 'defaults') -or $null -eq $SettingsObj.profiles.defaults) {
                        $SettingsObj.profiles | Add-Member -MemberType NoteProperty -Name 'defaults' -Value ([pscustomobject]@{}) -Force
                    }
                    $SettingsObj.profiles.defaults | Add-Member -MemberType NoteProperty -Name 'colorScheme' -Value 'Sub Theme' -Force
                }

                $OutJson = $SettingsObj | ConvertTo-Json -Depth 32
                Set-Content -LiteralPath $SettingsPath -Value $OutJson -Encoding UTF8
                Write-Ok "Added 'Sub Theme' color scheme to: $SettingsPath (backup: $BackupPath)"
            }
            catch {
                Write-Warn "Could not update $SettingsPath : $($_.Exception.Message)"
            }
        }
    }
}
catch {
    Write-Warn "Windows Terminal configuration encountered a non-fatal error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor DarkCyan
Write-Host "  Sub Theme (Gotland Navy) applied to Windows 11!" -ForegroundColor Cyan
Write-Host "  - Cycle wallpapers : .\apply-theme.ps1 -WallpaperIndex 2 (1..4)" -ForegroundColor Gray
Write-Host "  - Revert to default: .\apply-theme.ps1 -Revert" -ForegroundColor Gray
Write-Host "========================================================================" -ForegroundColor DarkCyan
