﻿if (-not (Get-Module VstsTaskSdk))
{
    Import-Module ".\ps_modules\VstsTaskSdk\VstsTaskSdk.psd1"
}

function Find-TfDirectory {
	$path = ""
	switch ($Find)
	{
		"VisualStudio"
		{
			$path = .\tools\vswhere -latest -products * -requires Microsoft.VisualStudio.TeamExplorer -property installationPath
			$path = join-path $path '\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\'
		}

		"Agent"
		{
			$path = Get-VstsTaskVariable -Name "Agent.HomeDirectory" -Require
			$path = join-path $path '\externals\vstshost\'
		}
	}
	
	return $path
}

function Find-VisualStudioTf {
    $ErrorActionPreference = 'Stop'


    return $path
}

function Find-AgentTf {
    $ErrorActionPreference = 'Stop'

    
    return $path
}

function Invoke-Tf
(
	$path,
	$workingDirectory,
	$command,
	$additionalArguments,
	$login,
	[switch]$xml
)
{
	$workingDirectory = Get-VstsInput -Name "WorkingDirectory"
	if (-not $workingDirectory)
	{
		$workingDirectory = Get-VstsTaskVariable -Name "System.DefaultWorkingDirectory" -Require
	}

	$additionalArguments = Get-VstsInput -Name "Arguments"

	$login = Get-VstsInput -Name "Login" -Default "OAuth"
	switch ($login)
	{
		"OAuth"{ 
			$endpoint     = Get-VstsEndpoint -Name SystemVssConnection -Require
			$username     = "."
			$password     = $endpoint.auth.parameters.AccessToken
			$collection   = Get-VstsTaskVariable "System.TeamFoundationCollectionUri" -Require
			$additionalArguments = "$additionalArguments /loginType:OAuth"
		}
		"EndPoint"{
			$endpointName = Get-VstsInput "EndpointName" -Require
			$endpoint     = Get-VstsEndpoint -Name $endpointName -Require
			$username     = $endpoint.auth.parameters.Username
			$password     = $endpoint.auth.parameters.Password
			$collection   = $endpoint.Url
		}
		"Username"{
			$username     = Get-VstsInput -Name "Username" -Require
			$password     = Get-VstsInput -Name "Password" -Require
			$collection   = Get-VstsTaskVariable "Collection" -Require
		}
		""{}
	}

	if ($username)
	{
		$additionalArguments = "$additionalArguments /login:$username,$password"
	}

	if ($collection)
	{
		$additionalArguments = "$additionalArguments /collection:$collection"
	}

	if ($xml)
	{
		$additionalArguments = "$additionalArguments /format:xml"
	}
	
	Invoke-VstsTool -FileName $path -Arguments "vc $command $additionalArguments /noprompt" -WorkingDirectory $workingdirectory
}

$tfDirectory = Find-TfDirectory -Method "Agent"
$tf = join-path $tfDirectory '\tf.exe'

function Invoke-Action($action)
{
	switch ($action)
	{
		"Command"
		{
			$command = Get-VstsInput -Name "Command" -Require
			$command = Get-VstsInput -Name "Arguments"
			Invoke-Tf -path $tf -command $command -additionalArguments $additionalArguments 
		}
		"Custom"
		{
			$command = Get-VstsInput -Name "Arguments" -Require
			Invoke-Tf -path $tf -additionalArguments $additionalArguments
		}
		"Recipe"
		{
			$command = Get-VstsInput -Name "Recipe" -Require
			switch ($recipe)
			{
				"UpdateGatedChanges"
				{
					Run-RecipeUpdateGatedChanges
				}
				"MapAndGet"
				{
					Run-RecipeMapAndGet
				}
			}
		}
	}
}

function Run-RecipeUpdateGatedChanges()
{
	$BuildReason = Get-VstsTaskVariable("Build.Reason") -Require
	$ValidReasons = @("CheckInShelveset", "ValidateShelveset")

	if ($ValidReasons.Contains($BuildReason))
	{
		Write-Output "Pending changes."
		$adds     = Get-VstsInput -AsBool -Name "Adds"
		$deletes  = Get-VstsInput -AsBool -Name "Deletes"
		$noIgnore = Get-VstsInput -AsBool -Name "NoIgnore"
		$exclude  = ((Get-VstsInput -Name "Exclude")  -split "\\r?\\n|;" | %{"""$($_.Trim())"""}) -join ","
		$itemspec = ((Get-VstsInput -Name "ItemSpec") -split "\\r?\\n|;" | %{"""$($_.Trim())"""}) -join " "
		$recursion = Get-VstsInput -AsBool -Name "Recursion"

		$reconcileArguments = "/promote"
		if ($recursion)
		{
			$reconcileArguments += " /recursive"
		}
		if ($adds)
		{
			$reconcileArguments += " /adds"
		}
		if ($deletes)
		{
			$reconcileArguments += " /deletes"
		}
		if ($noIgnore)
		{
			$reconcileArguments += " /noIgnore"
		}
		if ($exclude)
		{
			$reconcileArguments += " /exclude:$exclude"
		}
		if ($itemspec)
		{
			$reconcileArguments += " $itemspec"
		}
		# tf vc reconcile /promote [/adds] [/deletes] [/diff] [/noprompt] [/preview]
		#            [/recursive] [/noignore] [/exclude:itemspec1,itemspec2,...]
		#            [itemspec]

		Invoke-Tf -path $tf -command "reconcile" -additionalArguments $reconcileArguments

		$BuildId = Get-VstsTaskVariable("Build.BuildId") -Require
		$ShelvesetName = "_Build_$BuildId"
		Write-Output "Updating shelveset ($ShelvesetName)."

		# tf vc shelve [/replace] [/comment:("comment"|@commentfile)]
		#         [shelvesetname] [/validate] [/noprompt]
		#         [/login:username,[password]] [/new]
		Invoke-Tf -path $tf -command "shelve" -additionalArguments "/replace $ShelvesetName"
		Write-VstsSetResult -Result Succeeded -Message "Completed"
	}
	else
	{
		Write-VstsSetResult -Result Skipped -Message "Skipped"
	}
}

function Run-RecipeMapAndGet()
{

}

$action = Get-VstsInput -Name "Action" -Require
Invoke-Action $action