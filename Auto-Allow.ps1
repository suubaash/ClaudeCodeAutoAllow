<#
.SYNOPSIS
    Auto-approves ALL Claude Code desktop permission prompts across all sessions.

.DESCRIPTION
    Polls every Claude desktop window via UI Automation. When an "Allow once"
    button is found in ANY session window, it clicks it using multiple methods:
    1. UIA Invoke pattern
    2. UIA click via clickable point
    3. Focus window + Ctrl+Enter keyboard shortcut

    Handles multiple sessions simultaneously — checks all windows each cycle.

.PARAMETER IntervalMs
    Polling interval in milliseconds. Default 10000 (10 seconds).

.PARAMETER Inspect
    Dump all buttons across all Claude windows and exit.
#>
[CmdletBinding()]
param(
    [int]$IntervalMs = 10000,
    [string[]]$ProcessName = @('Claude'),
    [switch]$Inspect
)

$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
}
'@

$AE       = [System.Windows.Automation.AutomationElement]
$Cond     = [System.Windows.Automation.Condition]
$TS       = [System.Windows.Automation.TreeScope]::Descendants
$CtrlProp = [System.Windows.Automation.AutomationElement]::ControlTypeProperty
$BtnType  = [System.Windows.Automation.ControlType]::Button
$InvokePat = [System.Windows.Automation.InvokePattern]::Pattern

# Exact button names that mean "approve this prompt"
$AllowNames = @('Allow once', 'Allow always', 'Always allow', 'Yes, allow')

function Get-AllClaudeElements {
    $procIds = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id)
    if (-not $procIds) { return @() }

    $root = $AE::RootElement
    $all = $root.FindAll($TS, $Cond::TrueCondition)
    $result = @()
    foreach ($el in $all) {
        try {
            if ($procIds -contains $el.Current.ProcessId) { $result += $el }
        } catch { }
    }
    return $result
}

function Find-AllAllowButtons {
    $elements = Get-AllClaudeElements
    if (-not $elements) { return @() }

    $btnCond = New-Object System.Windows.Automation.PropertyCondition($CtrlProp, $BtnType)
    $hits = @()
    foreach ($el in $elements) {
        try {
            $buttons = $el.FindAll($TS, $btnCond)
            foreach ($b in $buttons) {
                try {
                    $name = $b.Current.Name
                    if (-not $name -or -not $b.Current.IsEnabled) { continue }
                    foreach ($allowed in $AllowNames) {
                        if ($name -like "*$allowed*") {
                            $hits += [pscustomobject]@{
                                Element = $b
                                Name    = $name
                                PID     = $b.Current.ProcessId
                            }
                            break
                        }
                    }
                } catch { }
            }
        } catch { }
    }
    return $hits
}

function Get-WindowHandle($element) {
    try {
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $current = $element
        while ($current) {
            $hwnd = $current.Current.NativeWindowHandle
            if ($hwnd -ne 0) { return [IntPtr]$hwnd }
            $current = $walker.GetParent($current)
        }
    } catch { }
    return [IntPtr]::Zero
}

function Click-AllowButton($hit) {
    $name = $hit.Name

    # Method 1: UIA Invoke
    try {
        $pattern = $hit.Element.GetCurrentPattern($InvokePat)
        $pattern.Invoke()
        Write-Host ("{0}  approved (invoke): '{1}' [PID {2}]" -f (Get-Date -Format 'HH:mm:ss'), $name, $hit.PID) -ForegroundColor Green
        return $true
    } catch { }

    # Method 2: Direct mouse click on the button's clickable point
    try {
        $pt = $hit.Element.GetClickablePoint()
        [Win32]::SetCursorPos([int]$pt.X, [int]$pt.Y)
        Start-Sleep -Milliseconds 100
        [Win32]::mouse_event(0x02, 0, 0, 0, 0)  # MOUSEEVENTF_LEFTDOWN
        [Win32]::mouse_event(0x04, 0, 0, 0, 0)  # MOUSEEVENTF_LEFTUP
        Write-Host ("{0}  approved (click):  '{1}' [PID {2}]" -f (Get-Date -Format 'HH:mm:ss'), $name, $hit.PID) -ForegroundColor Green
        return $true
    } catch { }

    # Method 3: Focus window + Ctrl+Enter
    try {
        $prevFg = [Win32]::GetForegroundWindow()
        $hwnd = Get-WindowHandle $hit.Element
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32]::ShowWindow($hwnd, 9) | Out-Null
            [Win32]::SetForegroundWindow($hwnd) | Out-Null
            Start-Sleep -Milliseconds 300
            [System.Windows.Forms.SendKeys]::SendWait('^{ENTER}')
            Start-Sleep -Milliseconds 200
            if ($prevFg -ne [IntPtr]::Zero) {
                [Win32]::SetForegroundWindow($prevFg) | Out-Null
            }
            Write-Host ("{0}  approved (keys):   '{1}' [PID {2}]" -f (Get-Date -Format 'HH:mm:ss'), $name, $hit.PID) -ForegroundColor Green
            return $true
        }
    } catch { }

    Write-Host ("{0}  FAILED all methods: '{1}' [PID {2}]" -f (Get-Date -Format 'HH:mm:ss'), $name, $hit.PID) -ForegroundColor Red
    return $false
}

# --- Inspect mode ---
if ($Inspect) {
    $elements = Get-AllClaudeElements
    if (-not $elements) { Write-Host "No Claude windows found." -ForegroundColor Yellow; return }
    $btnCond = New-Object System.Windows.Automation.PropertyCondition($CtrlProp, $BtnType)
    Write-Host "Buttons across all Claude windows:" -ForegroundColor Cyan
    foreach ($el in $elements) {
        try {
            foreach ($b in $el.FindAll($TS, $btnCond)) {
                try {
                    $n = $b.Current.Name
                    $en = if ($b.Current.IsEnabled) { 'on' } else { 'off' }
                    $pid = $b.Current.ProcessId
                    Write-Host ("  [{0}] PID {1}: '{2}'" -f $en, $pid, $n)
                } catch { }
            }
        } catch { }
    }
    return
}

# --- Main loop ---
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Auto-Allow running - ALL Claude sessions" -ForegroundColor Green
Write-Host "  Polling every ${IntervalMs}ms | Press Ctrl+C to stop" -ForegroundColor Green
Write-Host "  Methods: UIA Invoke -> Mouse Click -> Ctrl+Enter" -ForegroundColor DarkGray
Write-Host "================================================================" -ForegroundColor Cyan

while ($true) {
    try {
        $hits = Find-AllAllowButtons
        if ($hits) {
            Write-Host ("{0}  found {1} prompt(s)..." -f (Get-Date -Format 'HH:mm:ss'), $hits.Count) -ForegroundColor Yellow
            foreach ($hit in $hits) {
                Click-AllowButton $hit | Out-Null
                Start-Sleep -Milliseconds 500
            }
        }
    } catch {
        Write-Host ("{0}  warn: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message) -ForegroundColor DarkYellow
    }
    Start-Sleep -Milliseconds $IntervalMs
}
