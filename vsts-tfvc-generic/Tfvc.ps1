if (-not (Get-Module VstsTaskSdk))
{
    Import-Module ".\ps_modules\VstsTaskSdk\VstsTaskSdk.psd1"
}

function Find-VisualStudioTf {
    $ErrorActionPreference = 'Stop'

    $path = .\tools\vswhere -latest -products * -requires Microsoft.VisualStudio.TeamExplorer -property installationPath
    $path = join-path $path '\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\tf.exe'
    return $path
}

function Find-AgentTf {
    $ErrorActionPreference = 'Stop'

    $path = Get-VstsTaskVariable -Name "Agent.HomeDirectory" -Require
    $path = join-path $path '\externals\vstshost\tf.exe'
    return $path
}

$tf = Find-VisualStudioTf

Invoke-VstsTool -FileName $tf -Arguments "vc"