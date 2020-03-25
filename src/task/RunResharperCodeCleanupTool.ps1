param
(
    [string] $solutionOrProjectPath = $(throw 'solutionOrProjectPath is mandatory, please provide a value.'),
    [string] $commandLineInterfacePath = '',
    [string] $additionalArguments = '',
    [string] $buildId = 'Unlabeled_Build',
    [string] $resultsPathOverride = $null,
    [string] $resharperNugetVersion = 'Latest',
    [string] $onlyCleanUpSpecifiedFiles = 'false',
    [string] $filesToCleanUp = ''
)

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
    $tempDownloadFolder = $Env:BUILD_STAGINGDIRECTORY
    
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
        $solutionDirectory = [IO.Path]::GetDirectoryName($solutionOrProjectFullPath) + '\';

        $relativeFiles = $filesToCleanUp.Split(';', [StringSplitOptions]::RemoveEmptyEntries) | 
            ForEach-Object {
                $absolutePath = [IO.Path]::Combine($env:BUILD_SOURCESDIRECTORY, $_);
            
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

$taskCommonTools = 'Microsoft.TeamFoundation.DistributedTask.Task.Common'
if (Get-Module -ListAvailable -Name $taskCommonTools) 
{
    Write-Output -InputObject 'Preparing to add summary to build results'
}
else 
{
    Throw [IO.FileNotFoundException] "Module $taskCommonTools is not installed. If using a custom build controller ensure that this library is correctly installed and available for use in PowerShell."
}

Import-Module -Name $taskCommonTools
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
