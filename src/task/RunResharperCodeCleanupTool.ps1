[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation
try {
    [string] $buildId = Get-VstsTaskVariable -Name Build.BuildId
    [string] $buildStagingDirectory = Get-VstsTaskVariable -Name Build.StagingDirectory
    [string] $buildSourcesDirectory = Get-VstsTaskVariable -Name Build.SourcesDirectory

    [string] $solutionOrProjectPath = Get-VstsInput -Name solutionOrProjectPath
    [string] $commandLineInterfacePath = Get-VstsInput -Name commandLineInterfacePath
    [string] $additionalArguments = Get-VstsInput -Name additionalArguments
    [string] $resultsPathOverride = Get-VstsInput -Name resultsPathOverride
    [string] $resharperNugetVersion = Get-VstsInput -Name resharperNugetVersion
    [string] $onlyCleanUpSpecifiedFiles = Get-VstsInput -Name onlyCleanUpSpecifiedFiles
    [string] $filesToCleanUp = Get-VstsInput -Name filesToCleanUp


    function Set-Results 
    {
        param(
            [Parameter(Mandatory)]
            [string]
            $summaryMessage,

            [Parameter(Mandatory)]
            [ValidateSet('Succeeded', 'Failed')]
            [string]
            $buildResult
        )

        Write-Output -InputObject ('##vso[task.complete result={0};]{1}' -f $buildResult, $summaryMessage)
        Add-Content -Path $summaryFilePath -Value ($summaryMessage)
    }

    Write-Output -InputObject "Cleaning up code for $solutionOrProjectPath"

    # Run code cleanup
    $filesToCleanUp = $filesToCleanUp.Trim().Trim('"').Trim()
    $additionalArguments = $additionalArguments.Trim().Trim('"').Trim()
    $runCleanup = $true

    if ($onlyCleanUpSpecifiedFiles -eq 'true' -and [string]::IsNullOrWhitespace($filesToCleanUp))
    {
        $runCleanup = false
    }

    if ($runCleanup) 
    {
        $fileList = $filesToCleanUp.Replace(';', "`n")
        Write-Output -InputObject "Files to clean-up:`n$fileList"
    
        $cleanupCodeExePath = [IO.Path]::GetFullPath([IO.Path]::Combine($commandLineInterfacePath, 'CleanupCode.exe'))
        $tempDownloadFolder = $buildStagingDirectory

        if (!(Test-Path -Path $cleanupCodeExePath)) 
        {
            # Download Resharper from nuget
            $useSpecificNuGetVersion = $resharperNugetVersion -and $resharperNugetVersion -ne 'Latest'
        
            $downloadMessage = 'No pre-installed Resharper CLT was found'
            if ($useSpecificNuGetVersion)
            {
                $downloadMessage += ", downloading version $resharperNugetVersion from nuget.org..."
            }
            else 
            {
                $downloadMessage += ', downloading the latest from nuget.org...'
            }
          
            Write-Output -InputObject $downloadMessage
          
            $nugetExeLocation = [IO.Path]::Combine($PSScriptRoot, '.nuget')
          
            Copy-Item -Path $nugetExeLocation\* -Destination $tempDownloadFolder
          
            $nugetExeLocation = [IO.Path]::Combine($tempDownloadFolder, 'nuget.exe')
          
            $nugetArguments = 'install JetBrains.ReSharper.CommandLineTools -source https://api.nuget.org/v3/index.json'
            if ($useSpecificNuGetVersion)
            {
                $nugetArguments += " -Version $resharperNugetVersion"
            }
          
            Start-Process -FilePath "$nugetExeLocation" -ArgumentList $nugetArguments -WorkingDirectory $tempDownloadFolder -Wait
          
            $resharperPreInstalledDirectoryPath = [IO.Directory]::EnumerateDirectories($tempDownloadFolder, '*JetBrains*')[0]
            if (!(Test-Path -Path $resharperPreInstalledDirectoryPath)) 
            {
                Throw [IO.FileNotFoundException] "CleanupCode.exe was not found at $cleanupCodeExePath or $resharperPreInstalledDirectoryPath"
            }
          
            Write-Output -InputObject 'Resharper CLT downloaded'
          
            $commandLineInterfacePath = [IO.Path]::GetFullPath([IO.Path]::Combine($resharperPreInstalledDirectoryPath, 'tools'))
            $cleanupCodeExePath = [IO.Path]::GetFullPath([IO.Path]::Combine($commandLineInterfacePath, 'CleanupCode.exe'))
        }

        if (!(Test-Path -Path $cleanupCodeExePath)) 
        {
            Throw [IO.FileNotFoundException] "CleanupCode.exe was not found at $cleanupCodeExePath"
        }
      
        [string] $solutionOrProjectFullPath = [IO.Path]::GetFullPath($solutionOrProjectPath.Replace("`"",''))
      
        if (!(Test-Path -Path $solutionOrProjectFullPath)) 
        {
            Throw [IO.FileNotFoundException] "No solution or project found at $solutionOrProjectFullPath"
        }
      
        $targetSolutionOrProjectFullPath = $solutionOrProjectFullPath;
      
        $solutionExtension = [IO.Path]::GetExtension($solutionOrProjectFullPath);
        if ($solutionExtension -eq '.slnf') {
            $slnf = Get-Content $solutionOrProjectFullPath -Raw | ConvertFrom-Json;

            $slnfDirectory = [IO.Path]::GetDirectoryName($solutionOrProjectFullPath);
            $targetSolutionOrProjectFullPath = [IO.Path]::Combine($slnfDirectory, $slnf.solution.path);
        }
      
        if (!(Test-Path -Path $targetSolutionOrProjectFullPath)) 
        {
            Throw [IO.FileNotFoundException] "No solution or project found at $targetSolutionOrProjectFullPath"
        }
      
        [string] $resultsPath = [IO.Path]::GetFullPath([IO.Path]::Combine($commandLineInterfacePath, "Reports\CodeCleanupResults_$buildId.xml"))
        if ($resultsPathOverride)
        {
            if (!$resultsPathOverride.EndsWith('.xml')) 
            {
                $resultsPathOverride += '.xml'
            }

            $resultsPath = $resultsPathOverride
        }
      
        Write-Output -InputObject "Using Resharper Cleanup Code found at '$cleanupCodeExePath'"

        $arguments = ''
        if ($onlyCleanUpSpecifiedFiles -eq 'true')
        {
            $solutionDirectory = [IO.Path]::GetDirectoryName($targetSolutionOrProjectFullPath) + '\';
        
            $relativeFiles = $filesToCleanUp.Split(';', [StringSplitOptions]::RemoveEmptyEntries) | 
                ForEach-Object {
                    $absolutePath = [IO.Path]::Combine($buildSourcesDirectory, $_);
                
                    [Uri] $absoluteUri = New-Object -TypeName System.Uri -ArgumentList ($absolutePath);
                    [Uri] $solutionDirectoryUri = New-Object -TypeName System.Uri -ArgumentList ($solutionDirectory);
                
                    [Uri] $relativeUri = $solutionDirectoryUri.MakeRelativeUri($absoluteUri);
                
                    return $relativeUri.ToString();
                };
              
            $filesToCleanUp = [string]::Join(';', $relativeFiles);
              
            $arguments = $arguments + "--include=""$filesToCleanUp"""
        }

        $arguments = $arguments + "-o=""$resultsPath"" $additionalArguments ""$solutionOrProjectFullPath"""
        Write-Output -InputObject "Invoking CleanupCode.exe using arguments $arguments" 
        Start-Process -FilePath $cleanupCodeExePath -ArgumentList $arguments -Wait
    }

    $message = 'Cleanup done!'

    if (-not $runCleanup) 
    {
        $message = 'Nothing to cleanup!'
    }

    $summaryFilePath = [IO.Path]::GetFullPath([IO.Path]::Combine($tempDownloadFolder, 'Summary.md'))
    New-Item -Path $summaryFilePath -ItemType file -Force

    Set-Results -summaryMessage $message -buildResult Succeeded

    #Write-Output "##vso[task.addattachment type=Distributedtask.Core.Summary;name=Code Cleanup;]$summaryFilePath"

    If (Test-Path -Path $resultsPath) 
    {
        If (!$resultsPathOverride) 
        {
            Remove-Item -Path $resultsPath
        }
    }

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}