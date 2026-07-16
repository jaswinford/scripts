# =============================================
# Sharepoint Recursive Tree Copy
# =============================================
# Recursively copy the folder structure from one
# Sharepoint site to another

## Requirements
# - Read access to the entire source site
# - Read/Write access to the target site.
# - Enable custom scripts on the target site to allow writing (this is only good for 24 hours)

## Instructions
# 1. Create a new library on the Target site (There appears to be an issue with Sharepoint that prevents writing the new structure to the default Documents library)
# 2. Update $SourceSite and $TargetSite variables to point to the sites in question
# 3. Update $Source to be the Library whose tree you want to copy
# 4. Update $Target to be the Library created in step 1.
# 5. You will receive an interactive prompt to authenticate to Sharepoint online. Sign in as a user which has all the permissions outlined in the requirements

$SourceSite = "https://beehive3d.sharepoint.us/sites/CCA-CDE"
$TargetSite = "https://beehive3d.sharepoint.us/sites/QuestProgram"
$Source = "Shared Documents"
$Target = "Shared Documents"

# Establish connection to source site
Connect-PnPOnline -Url $SourceSite -Interactive -ClientId 6352604b-c498-4920-8be0-c95457d1f6f9 -Tenant beehive3d.onmicrosoft.us -AzureEnvironment USGovernmentHigh
$sourceConn = Get-PnPConnection

# Establish connection to target site
Connect-PnPOnline -Url $TargetSite -Interactive -ClientId 6352604b-c498-4920-8be0-c95457d1f6f9 -Tenant beehive3d.onmicrosoft.us -AzureEnvironment USGovernmentHigh
$targetConn = Get-PnPConnection

function Copy-Tree ($SourcePath, $TargetPath) {
 # We're only interested in Folders, so we only pull those
  $items = Get-PnPFolderInFolder -Identity $sourcePath -Connection $sourceConn
  foreach ($item in $items){
   # For each folder we find, make a copy then recursively call this function on it.
    $NextSource = "$SourcePath/$($item.Name)"
    $NextTarget = "$TargetPath/$($item.Name)"
    try{
      Add-PnPFolder -Name $item.Name -Folder $TargetPath -connection $targetConn
      Write-Output "Created Folder: $NextTarget"
    }
    catch {
      Write-Error $_.Exception
    }
    Copy-Tree -SourcePath $NextSource -TargetPath $NextTarget
  }

}

Write-Output "Copying tree from $source to $target"
Copy-Tree $Source $Target
