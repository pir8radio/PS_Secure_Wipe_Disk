# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("This script must be run as Administrator. Restarting with elevated privileges.")
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Load Windows Forms
Add-Type -AssemblyName System.Windows.Forms

# Hide the PowerShell console window
$hwnd = Get-Process -Id $PID | ForEach-Object { $_.MainWindowHandle }
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@
[Win32]::ShowWindow($hwnd, 0)

# ----------------------------
# 0. Only allow one instance
# ----------------------------
$restart = $true
$mutexName = "Global\DiskWipeMutex"
[bool]$isNew = $false
$mutex = [System.Threading.Mutex]::New($false, $mutexName, [ref]$isNew)
if (-not $isNew) {
    # If the mutex already exists, show a message and exit
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Another instance of the script is already running.", "Script Already Running", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

# ----------------------------
# 1. Disk Selection Form
# ----------------------------
while ($restart) {
$restart = $false
$form = New-Object System.Windows.Forms.Form
$form.Text = "Select Disk to Wipe"
$form.Size = New-Object System.Drawing.Size(400, 150)
$form.StartPosition = "CenterScreen"

# Set fixed vertical positions for controls
$labelY    = 10    # Y position for the main instruction label
$warningY  = 30    # Y position for the warning text
$comboBoxY = 50    # Y position for the ComboBox
$buttonY   = 80    # Y position for the OK and Cancel buttons

# Main instruction label
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select a disk to wipe from the list below:"
$label.Location = New-Object System.Drawing.Point(10, $labelY)
$label.AutoSize = $true
$form.Controls.Add($label)

# Warning text below the main label
$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Text = "Do not use on SSD's"
$warningLabel.Location = New-Object System.Drawing.Point(10, $warningY)
$warningLabel.AutoSize = $true
$warningLabel.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 8)
$warningLabel.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($warningLabel)

# ComboBox for disk selection
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Location = New-Object System.Drawing.Point(10, $comboBoxY)
$comboBox.Size = New-Object System.Drawing.Size(360, 20)
# List available disks
Get-Disk | ForEach-Object {
    $comboBox.Items.Add("Disk $($_.Number): $($_.FriendlyName), $([math]::Round($_.Size / 1GB, 2)) GB")
}
$form.Controls.Add($comboBox)

# OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object System.Drawing.Point(10, $buttonY)
$okButton.Add_Click({
    if ($comboBox.SelectedItem) {
        # Extract disk number using regex
        $form.Tag = $comboBox.SelectedItem -replace '^Disk (\d+):.*$', '$1'
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a disk before proceeding.", "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$form.Controls.Add($okButton)

# Cancel Button
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "Cancel"
$cancelButton.Location = New-Object System.Drawing.Point(90, $buttonY)
$cancelButton.Add_Click({
    $form.Tag = "CANCEL"
    $form.Close()
})
$form.Controls.Add($cancelButton)

# Refresh Button
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object System.Drawing.Point(180, $buttonY)
$refreshButton.Add_Click({
    # Clear and re-populate the ComboBox with the current list of disks
    $comboBox.Items.Clear()
    Get-Disk | ForEach-Object {
        $comboBox.Items.Add("Disk $($_.Number): $($_.FriendlyName), $([math]::Round($_.Size / 1GB, 2)) GB")
    }
    [System.Windows.Forms.MessageBox]::Show("Drive list has been refreshed.", "Refreshed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information)
})
$form.Controls.Add($refreshButton)

$form.ShowDialog()
$diskNumber = $form.Tag

# Exit if the user canceled
if ($diskNumber -eq "CANCEL") {
    Write-Host "Operation canceled by user."
    exit
}

# Validate disk selection and retrieve details
Write-Host "Selected Disk Number: $diskNumber"
$disk = Get-Disk -Number $diskNumber
if (-not $disk) {
    [System.Windows.Forms.MessageBox]::Show("Disk $diskNumber could not be detected. Please check the disk and try again.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}
if ($disk.Size -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("The selected disk reports a size of 0. Please ensure the disk is connected properly.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# ----------------------------
# 2. Estimate Time & Confirm
# ----------------------------
function Test-WriteSpeed {
    param (
        [int]$diskNumber,
        [string]$diskPath
    )

    $tempFilePath = "$diskPath\tempfile.bin"
    $blockSize = 64MB
    $totalSize = 1GB
    $totalWrites = $totalSize / $blockSize

    # Create a temporary file to test write speed
    try {
        # Start the timer
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        for ($i = 0; $i -lt $totalWrites; $i++) {
            $data = New-Object byte[] ($blockSize)
            [System.IO.File]::WriteAllBytes($tempFilePath, $data)
        }
        
        # Stop the timer
        $stopwatch.Stop()
        
        # Calculate the write speed in MB/s
        $writeSpeedMBps = $totalSize / $stopwatch.Elapsed.TotalSeconds / 1MB
        
        # Clean up the temporary file
        Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue

        return $writeSpeedMBps
    }
    catch {
        return $null
    }
}

# Create a loading screen
function Show-LoadingScreen {
    $loadingForm = New-Object System.Windows.Forms.Form
    $loadingForm.Text = "Testing disk write speed, please wait..."
    $loadingForm.Size = New-Object System.Drawing.Size(300, 100)
    $loadingForm.StartPosition = "CenterScreen"
    $loadingForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $loadingForm.ControlBox = $false
    $loadingForm.TopMost = $true

    $loadingForm.Show()
    return $loadingForm
}

# Find the drive letter for the selected disk
$diskPath = $null
$partitions = Get-Partition -DiskNumber $diskNumber

foreach ($partition in $partitions) {
    $volume = Get-Volume -Partition $partition
    if ($volume.DriveLetter) {
        $diskPath = "$($volume.DriveLetter):\"
        break
    }
}

if (-not $diskPath) {
    [System.Windows.Forms.MessageBox]::Show("No drive letter found for disk $diskNumber. Using estimated speed.", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# Show the loading screen
$loadingScreen = Show-LoadingScreen

# Test the write speed
$writeSpeedMBps = $null
if ($diskPath) {
    $writeSpeedMBps = Test-WriteSpeed -diskNumber $diskNumber -diskPath $diskPath
}

# Close the loading screen
$loadingScreen.Close()

if ($writeSpeedMBps -eq $null) {
    # Fall back to 10 seconds per GB if write speed cannot be determined
    $diskSizeGB = [math]::Ceiling($disk.Size / 1GB)
    $estimatedTimeSeconds = $diskSizeGB * 10
} else {
    # Estimate time based on write speed
    $diskSizeMB = [math]::Ceiling($disk.Size / 1MB)
    $estimatedTimeSeconds = $diskSizeMB / $writeSpeedMBps
}

$hours = [math]::Floor($estimatedTimeSeconds / 3600)
$minutes = [math]::Floor(($estimatedTimeSeconds % 3600) / 60)
$seconds = [math]::Round($estimatedTimeSeconds % 60)

# Confirmation Form
$confirmForm = New-Object System.Windows.Forms.Form
$confirmForm.Text = "Confirm Disk Wipe"
$confirmForm.Size = New-Object System.Drawing.Size(400, 200)
$confirmForm.StartPosition = "CenterScreen"

# Warning Label
$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Text = "Warning: You are about to wipe Disk $diskNumber. This action is irreversible. Do you wish to proceed?"
$warningLabel.AutoSize = $true
$warningLabel.Location = New-Object System.Drawing.Point(10, 10)
$warningLabel.MaximumSize = New-Object System.Drawing.Size(360, 0)
$confirmForm.Controls.Add($warningLabel)

# Estimated Time Label
$timeLabel = New-Object System.Windows.Forms.Label
$timeLabel.Text = "Estimated time to wipe disk: $hours hours $minutes minutes $seconds seconds."
$timeLabel.AutoSize = $true
$timeLabel.Location = New-Object System.Drawing.Point(10, 60)
$confirmForm.Controls.Add($timeLabel)

# Proceed Button
$proceedButton = New-Object System.Windows.Forms.Button
$proceedButton.Text = "Proceed"
$proceedButton.Location = New-Object System.Drawing.Point(10, 100)
$proceedButton.Add_Click({
    $confirmForm.Tag = "PROCEED"
    $confirmForm.Close()
})
$confirmForm.Controls.Add($proceedButton)

# Cancel Button on confirm form
$confirmCancelButton = New-Object System.Windows.Forms.Button
$confirmCancelButton.Text = "Cancel"
$confirmCancelButton.Location = New-Object System.Drawing.Point(100, 100)
$confirmCancelButton.Add_Click({
    $confirmForm.Tag = "CANCEL"
    $confirmForm.Close()
})
$confirmForm.Controls.Add($confirmCancelButton)

$confirmForm.ShowDialog()

if ($confirmForm.Tag -eq "CANCEL") {
    [System.Windows.Forms.MessageBox]::Show("Disk wipe operation canceled by user.", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    exit
}

# ----------------------------
# 3. Run DiskPart
# ----------------------------
# Create a temporary file with DiskPart commands
$tempFile = New-TemporaryFile
@"
    select disk $diskNumber
    clean all
"@ | Set-Content -Path $tempFile.FullName

# Debug: Show the contents of the temporary DiskPart script file
Write-Host "DiskPart commands written to temporary file:"
Get-Content -Path $tempFile.FullName | Out-String | Write-Host

# ----------------------------
# 4. Progress Form & Countdown
# ----------------------------
$progressForm = New-Object System.Windows.Forms.Form
$progressForm.Text = "Disk Wipe in Progress"
$progressForm.Size = New-Object System.Drawing.Size(400, 150)
$progressForm.StartPosition = "CenterScreen"

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = "Estimated time remaining: Calculating..."
$progressLabel.AutoSize = $true
$progressLabel.Location = New-Object System.Drawing.Point(10, 10)
$progressForm.Controls.Add($progressLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 40)
$progressBar.Size = New-Object System.Drawing.Size(360, 30)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressForm.Controls.Add($progressBar)

$cancelProgressButton = New-Object System.Windows.Forms.Button
$cancelProgressButton.Text = "Cancel"
$cancelProgressButton.Location = New-Object System.Drawing.Point(10, 80)
$cancelProgressButton.Add_Click({
    $progressForm.Tag = "CANCEL"
    $progressForm.Close()
})
$progressForm.Controls.Add($cancelProgressButton)

# Start DiskPart asynchronously
$argument = "/s `"$($tempFile.FullName)`""
$process = Start-Process -FilePath "diskpart.exe" -ArgumentList $argument -WindowStyle Hidden -PassThru
$processID = $process.Id

# Show the progress form (non-modal)
$progressForm.Show()

# Use a while loop to update the progress form and countdown
$elapsed = 0
while ($progressForm.Visible) {
    Start-Sleep -Seconds 1

    # If the user clicks Cancel…
    if ($progressForm.Tag -eq "CANCEL") {
        if ($processID) {
            Stop-Process -Id $processID -Force -ErrorAction SilentlyContinue
            $processID = $null
        }
        # Terminate VDS process if running
        $vdsProcess = Get-Process -Name "VDS" -ErrorAction SilentlyContinue
        if ($vdsProcess) {
            Stop-Process -Name "VDS" -Force -ErrorAction SilentlyContinue
        }
        $progressForm.Close()
        Remove-Item -Path $tempFile.FullName -Force
        exit
    }

    # Calculate progress (percentage based on elapsed time vs. estimated time)
    $progress = [math]::Floor(($elapsed / $estimatedTimeSeconds) * 100)
    $progressBar.Value = [math]::Min($progress, 100)

    # Calculate remaining time
    $remainingSeconds = $estimatedTimeSeconds - $elapsed
    $hours = [math]::Floor($remainingSeconds / 3600)
    $minutes = [math]::Floor(($remainingSeconds % 3600) / 60)
    $seconds = [math]::Round($remainingSeconds % 60)
    $progressLabel.Text = "Estimated time remaining: $hours hours $minutes minutes $seconds seconds"
    
    # Pump UI messages
    [System.Windows.Forms.Application]::DoEvents()

    $elapsed++

    # Check if DiskPart has finished
    if ($processID -and (-not (Get-Process -Id $processID -ErrorAction SilentlyContinue))) {
        $progressForm.Close()
    
        # Create a custom dialog with options
        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            "Disk $diskNumber has been securely wiped. Do you want to wipe another disk?",
            "Completed",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            $restart = $true
        } else {
            break
        }
    }
}
}

# ----------------------------
# 5. Clean Up
# ----------------------------
if ($processID -and (Get-Process -Id $processID -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $processID -Force -ErrorAction SilentlyContinue
}

$vdsProcess = Get-Process -Name "VDS" -ErrorAction SilentlyContinue
if ($vdsProcess) {
    Stop-Process -Name "VDS" -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $tempFile.FullName -Force
$mutex.ReleaseMutex()
$mutex.Dispose()
