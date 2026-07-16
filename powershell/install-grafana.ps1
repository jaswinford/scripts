# 1. Define the deployment payload that runs INSIDE each Windows VM (Literal Here-String)
$AlloyScriptPayload = @'
    $alloyConfigPath = "C:\Program Files\GrafanaLabs\Alloy\config.alloy"
    $installerPath   = "$env:TEMP\grafana-alloy-installer.exe"

    $alloyConfigContent = @"
// ============================================================================
// 1. METRICS COLLECTION (Windows Exporter)
// ============================================================================
prometheus.exporter.windows "local_windows_system" {
  enabled_collectors = ["cpu", "memory", "cs", "logical_disk", "net", "os", "system"]
}

// ============================================================================
// 2. METRICS SCRAPING
// ============================================================================
prometheus.scrape "scrape_metrics" {
  targets    = prometheus.exporter.windows.local_windows_system.targets
  forward_to = [prometheus.relabel.add_hostname.receiver]
}

// ============================================================================
// 3. METRICS PROCESSING (Relabeling)
// ============================================================================
prometheus.relabel "add_hostname" {
  forward_to = [prometheus.remote_write.prometheus_server.receiver]

  rule {
    target_label = "instance"
    replacement  = constants.hostname
  }
}

// ============================================================================
// 4. METRICS FORWARDING (Remote Write)
// ============================================================================
prometheus.remote_write "prometheus_server" {
  endpoint {
    url = "http://10.1.0.198:9090/api/v1/write"
  }
}
"@

    Write-Host "Checking for latest Grafana Alloy release..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $githubApiUrl = "https://api.github.com/repos/grafana/alloy/releases/latest"

    try {
        $releaseInfo = Invoke-RestMethod -Uri $githubApiUrl -UseBasicParsing
        $downloadUrl = ($releaseInfo.assets | Where-Object { $_.name -eq "alloy-installer-windows-amd64.exe" }).browser_download_url
        if (-not $downloadUrl) { throw "Installer asset not found." }
    } catch {
        Write-Error "GitHub API failure: $_"; exit 1
    }

    Write-Host "Downloading installer..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Running silent installation..."
    $installProcess = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
    if ($installProcess.ExitCode -ne 0) { Write-Error "Install failed"; exit 1 }

    Write-Host "Writing configuration..."
    $targetDir = Split-Path $alloyConfigPath
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    Set-Content -Path $alloyConfigPath -Value $alloyConfigContent -Force

    Write-Host "Starting Alloy service..."
    if (Get-Service -Name "Alloy" -ErrorAction SilentlyContinue) {
        Restart-Service -Name "Alloy" -Force
        Write-Host "Successfully configured and running!"
    } else {
        Write-Error "Alloy service missing post-install."
    }

    if (Test-Path $installerPath) { Remove-Item $installerPath -Force }
'@

# 2. Get all Windows VMs in the current Azure context that are running
Write-Host "Querying Azure subscription for all Windows Virtual Machines..." -ForegroundColor Cyan
$allWindowsVMs = Get-AzVM | Where-Object { $_.StorageProfile.OsDisk.OsType -eq "Windows" }

Write-Host "Found $($allWindowsVMs.Count) Windows VM(s). Starting parallel deployment..." -ForegroundColor Green

# 3. Process the deployment across all VMs in parallel (Up to 10 concurrently)
$allWindowsVMs | ForEach-Object -Parallel {
    $vmName = $_.Name
    $rgName = $_.ResourceGroupName
    $executionScript = $using:AlloyScriptPayload

    Write-Host "[+$vmName] Initiating Alloy deployment in resource group '$rgName'..." -ForegroundColor Yellow

    try {
        # Execute the string script inside the VM using the Azure VM Agent
        $result = Invoke-AzVMRunCommand -ResourceGroupName $rgName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $executionScript -ErrorAction Stop

        $output = $result.Value | Out-String
        Write-Host "[✓ $vmName] Deployment succeeded!`nOutput details:`n$output" -ForegroundColor Green
    }
    catch {
        Write-Host "[X $vmName] Critical deployment failure. Error: $_" -ForegroundColor Red
    }
} -ThrottleLimit 10
