# remove all modules, especially Pester so it does not 
# get in the way when we try to call our functions the 
# same way Pester calls them
get-module pester, pstr, mocking, stack, scope | remove-module 
$PSModuleAutoLoadingPreference = 'Stop'

# define mocking module to hold our functions
$mck = New-Module -Name Mocking {
    $_scope = 'mock'
    
    # import New-Mock from the binary    
    Import-Module "$psscriptroot\BinaryMocking.dll" -Force

    # define how mock is setup, this is called in the scope of
    # this module.
    # For the moment we just build the mockInfo object, but in the 
    # future we can build parameters for it and so on.
    $setupMock = {
        param(
            $FunctionName, 
            $MockWith, 
            $ParameterFilter
        ) 

        $mockId = $([Guid]::NewGuid().ToString('N'))
        $scope = Get-Scope
        $functionName = $FunctionName
        $mockWith = $MockWith
        $parameterFilter = $ParameterFilter

        $mockInfo = New-MockInfo `
            -MockId $mockId `
            -FunctionName $functionName `
            -DefiningScope $scope `
            -MockWith $mockWith `
            -ParameterFilter $parameterFilter

        Add-Mock -Mock $mockInfo
        $mockInfo
    }

    # this script is called with the result of the first script
    # it is invoked in non-local scope which results in the function
    # being defined outside out the New-Mock, not inside of it.
    # As a result the mocked function is shadowed, in the scope 
    # where New-Mock is called, and we don't have to manage mock
    # lifetime anymore.
    $createMock = {
        param($Mock)
                
        Invoke-Expression "function $($Mock.FunctionName) { 
            & (Get-Module Mocking) { 
                Add-MockCall -FunctionName '$($Mock.FunctionName)' -MockId '$($Mock.MockId)' 
            }
            &{ 
                Write-Verbose 'Invoking mocked function $($Mock.FunctionName)' 
                $($Mock.MockWith.ToString()) 
            } 
        }";
    }

    # we pass the scriptblocks to the C# code so
    # we can edit them, without recompiling over and over
    [BinaryMocking.NewMockCommand]::SetupMock = $setupMock
    [BinaryMocking.NewMockCommand]::CreateMock = $createMock


    # from here on it's just the usual mock stuff with some variations
    # this is not very important
    [PsObject[]]$script:mockCallHistory = @()
    [PsObject[]]$script:mockTable = @()

    function Add-Mock ($Mock) {
        $script:mockTable += $Mock
    }

    function New-MockInfo ([string]$MockId, [string]$FunctionName, [string]$Module, [ScriptBlock]$MockWith, [ScriptBlock]$ParameterFilter, $DefiningScope) {
        [pscustomobject]@{ 
            MockId          = $MockId
            FunctionName    = $FunctionName
            DefiningScope   = $DefiningScope
            MockWith        = $MockWith
            ParameterFilter = $ParameterFilter
        }
    }

    function Get-MockCallHistory {
        $script:mockCallHistory
    }

    function Get-MockTable {
        $script:mockTable
    }

    function Add-MockCall ($MockId, $FunctionName) {
        $script:mockCallHistory += [pscustomobject]@{ 
            MockId       = $MockId
            FunctionName = $FunctionName

            Scope        = Get-ScopeHistory
            Time         = (Get-Date)
        }
    }

    filter Filter-FunctionName ($FunctionName) {
        if ($FunctionName -eq $_.FunctionName) {
            $_
        }
    }

    function Get-MockCall ($FunctionName, $Times, $Scope) {
        $currentScope = (Get-Scope).Id
        $callHistory = Get-MockCallHistory | Filter-FunctionName $FunctionName
        $mockCalls = $callHistory | foreach { 
            
            $ids = ( $_.Scope | Select -Last ($scope + 1) ) | select -ExpandProperty id  
            if ($ids -contains $currentScope ) {
                $_
            }
        }

        $mockCalls
    }


}


$stck = New-Module -Name Stack {
    $_scope = 'stack'
    [Collections.Stack]$script:scopeStack = New-Object 'Collections.Stack';

    function New-Scope ([string]$Name, [string]$Hint, [string]$Id = [Guid]::NewGuid().ToString('N')) { 
        New-Object -TypeName PsObject -Property @{
            Id   = $Id
            Name = $Name
            Hint = $Hint
        }
    }

    function Push-Scope ($Scope) {
        $script:scopeStack.Push($Scope)
    }
    
    function Pop-Scope {
        $script:scopeStack.Pop()
    }

    function Get-Scope ($Scope = 0) {
        if ($Scope -eq 0) {
            $script:scopeStack.Peek()
            
        }
    }

    function Get-ScopeHistory {
        $history = $script:scopeStack.ToArray()
        [Array]::Reverse($history)
        $history
    }
}

# basic pester implenatation to see how it would look
# in real test code, without the hassle of running full
# pester
$pstr = New-Module -Name Pstr {
    $_scope = 'pstr'
    function Write-Screen ([string] $Value, [ConsoleColor] $Color, [int]$Margin) {
        Write-Host -ForegroundColor $Color (" " * 2 * $Margin + $Value)
    }
    function Block ($Name, $Test, $Hint) {
        $scope = New-Scope -Name $Name -Hint $Hint
        Push-Scope $scope

    
        &$Test # | Out-Null

        $null = Pop-Scope
        
    }

    function It ($Name, $Test) {
        $margin = @(Get-ScopeHistory).Count
        Write-Screen -Value "It - $Name {`n" -Color Green -Margin $margin 
        Block -Name $Name -Test $Test -Hint "It"
        Write-Screen -Value "}`n" -Color Green -Margin $margin
    }
    function Context ($Name, $Test) {
        $margin = @(Get-ScopeHistory).Count
        Write-Screen -Value "Context - $Name {" -Color Green -Margin $margin
        Block -Name $Name -Test $Test -Hint "Context"
        Write-Screen -Value "}" -Color Green -Margin $margin
    }

    function Describe ($Name, $Test) {
        $margin = @(Get-ScopeHistory).Count
        Write-Screen -Value "Describe - $Name {" -Color Green -Margin $margin
        Block -Name $Name -Test $Test -Hint "Describe"
        Write-Screen -Value "}" -Color Green -Margin $margin
    }
    
    function ShouldBe {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $Actual,

            [Parameter(Position = 1)]
            $Expected
        )
        if ($Actual -eq $Expected) {
            Write-Host 'Assertion match'
        }
        else {
            Write-Error "`r`nExpected: $Expected `r`nActual:   $Actual"
        }
    }       
}

$scope = New-Module -Name Scope {
    $_scope = 'scope'
    function Get-InternalSessionState {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ParameterSetName = 'FromScriptBlock')]
            [scriptblock]
            $ScriptBlock,
    
            [Parameter(Mandatory = $true, ParameterSetName = 'FromSessionState')]
            [Management.Automation.SessionState]
            $SessionState
        )
    
        
        $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
        if ("FromScriptBlock" -eq $PSCmdlet.ParameterSetName) {
            return [scriptblock].GetProperty('SessionStateInternal', $flags).GetValue($ScriptBlock, $null)
        }
        
        [Management.Automation.SessionState].GetProperty('Internal', $flags).GetValue($SessionState, $null)
    }

    function Set-ScriptBlockScope {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [ScriptBlock] $ScriptBlock,
            [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
            $SessionStateInternal,
            [Switch]$PassThru
        )
    
        $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
        $property = [ScriptBlock].GetProperty('SessionStateInternal', $flags)
        $property.SetValue($ScriptBlock, $SessionStateInternal, $null)
        if ($PassThru) {
            $ScriptBlock
        }
    }
    
    # store the session state of the caller, pester does this by default
    # when pester state is created, but having explicit cmdlet gives 
    # us chance to store the state more-explicitly, to make the behaviour
    # easier to understand.
    function Save-ScriptScope {
        [CmdletBinding()]
        param ()
        $script:scriptScope = Get-InternalSessionState -SessionState $PSCmdlet.SessionState
    }

    function Invoke-InScriptScope {
        [CmdletBinding()]
        param(
            [ScriptBlock] $ScriptBlock
        )
        
        $InternalSessionState = $script:scriptScope
        
        # copy the scriptblock, this avoids mutation
        # of the script block state, which could lead to 
        # confusing behavior if the caller reuses the same 
        # scriptblock elsewhere
        $scriptBlockCopy = [ScriptBlock]::Create($ScriptBlock)

        # define internal session state of the scriptblock to make
        # it invoke in the correct scope
        $InternalSessionState | Set-ScriptBlockScope $scriptBlockCopy
        &$scriptBlockCopy
    }

    function Invoke-InModuleScope {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, ParameterSetName = "Module", ValueFromPipeline = $true)]
            [Management.Automation.PSModuleInfo] $Module,
            [Parameter(Mandatory = $true, ParameterSetName = "ModuleName", ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
            [String] $ModuleName,
            [Parameter(Mandatory = $true)]
            [ScriptBlock]
            $ScriptBlock
        )

        if ("ModuleName" -eq $PSCmdlet.ParameterSetName) {
            $Module = Get-Module -Name $ModuleName
        }

        # the same thing as in Invoke-InScriptScope happens here
        # but & automatically uses the session state of the module
        # to invoke the scriptblock
        &$Module $ScriptBlock
    }

    Export-ModuleMember -Function 'Invoke-InModuleScope', 'Save-ScriptScope', 'Invoke-InScriptScope'
}

Import-Module $mck -Force
Import-Module $stck -Force
Import-Module $pstr -Force
Import-Module $scope -Force