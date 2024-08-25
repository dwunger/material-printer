function Ensure-Path {
    param (
        [string] $path
    )

    if (-not (Test-Path -Path (Split-Path -Path $path -Parent))) {
        mkdir (Split-Path -Path $path -Parent)
    }

}

function Walk-Path ([string] $Path) {
    return Walk-PathHelper -Path $Path -BasePath $Path
}

function Walk-PathHelper ([string] $Path, [string] $BasePath) {
    $AllPaths = @()

    # Skip processing if this is a .git folder
    if ((Split-Path $Path -Leaf) -eq '.git') {
        return $AllPaths
    }

    foreach ($File in (ls $Path -File)) {
        $RelativePath = "" + ($Path + '/' + $File.Name).Substring($BasePath.Length + 1)
        $AllPaths += $RelativePath
    }
    
    foreach ($Dir in (ls $Path -Directory)) {
        $SubPath = $Path + '/' + $Dir.Name
        $AllPaths += Walk-PathHelper $SubPath $BasePath
    }
    
    
    return $AllPaths
}

function Query-Parameter {
    param (
        [string] $File,
        [string] $Parameter
    )
    
    if ( -not (Test-Path -Path $File) ) {
        Write-Error("Manifest not found at path:" + $File) 
    }

    $Contents = Get-Content -Path $File
    foreach ($Line in $Contents) {
        if (!$Line.Contains('=')) {
            continue
        }
        $Line = $Line -split '=', 2
        if ($Line[0].Trim() -eq $Parameter) {
            return $Line[1].Trim()
        }
    }
    return $null
}

function Convert-PathtoURI {
    param (
        [string] $Path
    )

    $RepoName = Query-Parameter -File .\MANIFEST -Parameter "GIT_REPO"
    
    return 'https://raw.githubusercontent.com/' + $RepoName + '/refs/heads/main/' + $Path
    
}

function Format-PathtoSysPath {
    param(
        [string] $Path
    )
    
    return ".\" + $Path.Replace('/', '\')
}

function Query-RemoteManifest {
    param(
        [string] $Parameter
    )

    $ManifestURI = Convert-PathtoURI -Path "MANIFEST"
    $TempFile = [System.IO.Path]::GetTempFileName()

    Ensure-Path $TempFile
    # This is merely an observer. It shouldn't be overwriting the local manifest, just observing the remote.
    # We'll write to a temp file then use Query-Parameter to get the version information
    Invoke-WebRequest -Uri $ManifestURI -OutFile $TempFile
    $value = Query-Parameter -File $TempFile -Parameter $Parameter

    Remove-Item $TempFile  

    return $value
}

# Get a list of URIs corresponding to each file in the remote INDEX file
function Get-RemoteIndexURIs {
    $IndexURI = Convert-PathtoURI -Path "INDEX"
    $RemoteIndex = Invoke-WebRequest -Uri $IndexURI

    # convert content to byte array and skip BOM bytes. not sure where these are coming from
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($RemoteIndex.Content)
    if ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $Content = [System.Text.Encoding]::UTF8.GetString($bytes[3..($bytes.Length-1)])
    } else {
        $Content = $RemoteIndex.Content
    }

    $FileList = $Content -split "`r?`n" | 
                ForEach-Object { $_.Trim() } | 
                Where-Object { $_ -ne "" }

    $URIList = @()
    foreach ($File in $FileList) {
        $URIList += (Convert-PathtoURI -Path $File)
    }

    return $URIList
}

function Get-RemoteIndexPaths {
    $IndexURI = Convert-PathtoURI -Path "INDEX"
    $RemoteIndex = Invoke-WebRequest -Uri $IndexURI

    # convert content to byte array and skip BOM bytes. not sure where these are coming from
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($RemoteIndex.Content)
    if ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        $Content = [System.Text.Encoding]::UTF8.GetString($bytes[3..($bytes.Length-1)])
    } else {
        $Content = $RemoteIndex.Content
    }

    $FileList = $Content -split "`r?`n" | 
                ForEach-Object { $_.Trim() } | 
                Where-Object { $_ -ne "" }

    $PathList = @()
    foreach ($File in $FileList) {
        $PathList += (Format-PathtoSysPath -Path $File)
    }

    return $PathList
}

function Update-Client {

    $FilePaths = Get-RemoteIndexPaths
    $FileURIs = Get-RemoteIndexURIs

    $headers = @{
        "Cache-Control" = "no-cache, no-store, must-revalidate"
        "Pragma"      = "no-cache"
        "Expires"     = "0"
    }

    for ($i = 0; $i -lt $FileURIs.Length; $i++) {
        Ensure-Path $FilePaths[$i]
        Invoke-WebRequest -Uri $FileURIs[$i] -Headers $headers -OutFile $FilePaths[$i]
    }

}

function Update-ClientVerbose {
    # Create a new logger instance
    $logger = [UpdateLogger]::new()
    
    $FilePaths = Get-RemoteIndexPaths
    $FileURIs = Get-RemoteIndexURIs
    
    # Initialize the update process
    $logger.StartUpdate($FileURIs.Length)
    
    for ($i = 0; $i -lt $FileURIs.Length; $i++) {
        # Log pending status
        $logger.LogFileStatus($FilePaths[$i], "Pending")
        
        # Log downloading status
        $logger.LogFileStatus($FilePaths[$i], "Downloading")
        
        Ensure-Path $FilePaths[$i]

        # Perform the actual download
        Invoke-WebRequest -Uri $FileURIs[$i] -OutFile $FilePaths[$i]
        
        # Log completed status
        $logger.LogFileStatus($FilePaths[$i], "Downloaded")
    }
    
    # Complete the update process
    $logger.CompleteUpdate()
}
