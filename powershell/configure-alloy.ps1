# 1. Define the deployment payload (Config Update Only) inside a literal Here-String
$AlloyConfigPayload = @'
    $alloyConfigPath = "C:\Program Files\GrafanaLabs\Alloy\config.alloy"

    $alloyConfigContent = @"
// ============================================================================
// 1. METRICS COLLECTION (Windows Exporter)
// ============================================================================
prometheus.exporter.windows "local_windows_system" {
  enabled_collectors = ["cpu", "cs", "logical_disk", "memory", "net", "os", "system"]
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

    Write-Host "Updating local configuration file at $alloyConfigPath..."
    $targetDir = Split-Path $alloyConfigPath
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # Overwrite the old layout
    Set-Content -Path $alloyConfigPath -Value $alloyConfigContent -Force

    Write-Host "Cycling the Grafana Alloy engine..."
    if (Get-Service -Name "Alloy" -ErrorAction SilentlyContinue) {
        Restart-Service -Name "Alloy" -Force
        Write-Host "Success: Configuration pushed and service restarted!"
    } else {
        Write-Error "Alloy service is not registered on this host. Configuration updated, but cannot cycle service."
    }
'@

# 2. Collect all target Windows environments
Write-Host "Querying Azure subscription for all target Windows Virtual Machines..." -ForegroundColor Cyan
$allWindowsVMs = Get-AzVM | Where-Object { $_.StorageProfile.OsDisk.OsType -eq "Windows" }

Write-Host "Found $($allWindowsVMs.Count) Windows VM(s). Executing parallel configuration updates..." -ForegroundColor Green

# 3. Stream config payload updates out to the host pool simultaneously
$allWindowsVMs | ForEach-Object -Parallel {
    $vmName = $_.Name
    $rgName = $_.ResourceGroupName
    $executionScript = $using:AlloyConfigPayload

    Write-Host "[+$vmName] Syncing configuration profile..." -ForegroundColor Yellow

    try {
        # Secure execution via Azure VM Guest Agent framework
        $result = Invoke-AzVMRunCommand -ResourceGroupName $rgName -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptString $executionScript -ErrorAction Stop

        $output = $result.Value | Out-String
        Write-Host "[✓ $vmName] Synced cleanly!`nDetails:`n$output" -ForegroundColor Green
    }
    catch {
        Write-Host "[X $vmName] Update pipeline blocked. RPC or VM agent connection failed. Error: $_" -ForegroundColor Red
    }
}
