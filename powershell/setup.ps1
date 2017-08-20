# remove all modules, especially Pester so it does not 
# get in the way when we try to call our functions the 
# same way Pester calls them
get-module pester, pstr, mocking, stack | remove-module 
$PSModuleAutoLoadingPreference = 'Stop'

# define mocking module to hold our functions
$mck = New-Module -Name Mocking {
    
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

    function New-MockInfo ([string]$MockId, [string]$FunctionName, [string]$Module, [ScriptBlock]$MockWith, [ScriptBlock]$ParameterFilter, $DefiningScope)
    {
        [pscustomobject]@{ 
            MockId = $MockId
            FunctionName = $FunctionName
            DefiningScope = $DefiningScope
            MockWith = $MockWith
            ParameterFilter = $ParameterFilter
        }
    }

    function Get-MockCallHistory {
        $script:mockCallHistory
    }

    function Get-MockTable {
        $script:mockTable
    }

    function Add-MockCall ($MockId, $FunctionName)  {
        $script:mockCallHistory += [pscustomobject]@{ 
            MockId = $MockId
            FunctionName = $FunctionName

            Scope = Get-ScopeHistory
            Time = (Get-Date)
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
            
            $ids=  ( $_.Scope | Select -Last ($scope + 1) ) | select -ExpandProperty id  
            if ($ids -contains $currentScope )
            {
                $_
            }
        }

        $mockCalls
    }


}


$stck = New-Module -Name Stack {
    [Collections.Stack]$script:scopeStack = New-Object 'Collections.Stack';

    function New-Scope ([string]$Name, [string]$Hint, [string]$Id = [Guid]::NewGuid().ToString('N')) { 
        New-Object -TypeName PsObject -Property @{
            Id = $Id
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
        if ($Scope -eq 0) 
        {
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
    function Block ($Name, $Test, $Hint) {
        Write-Host -ForegroundColor Green "Entering $Name" 
        $scope = New-Scope -Name $Name -Hint $Hint
        Push-Scope $scope

    
        &$Test # | Out-Null

        $null = Pop-Scope
        Write-Host -ForegroundColor Green "Leaving $Name" 
    }

    function It ($Name, $Test) {
        Block -Name $Name -Test $Test -Hint "It"
    }
    function Context ($Name, $Test) {
        Block -Name $Name -Test $Test -Hint "Context"
    }

    function Describe ($Name, $Test) {
        Block -Name $Name -Test $Test -Hint "Describe"
    }
    
    function ShouldBe {
        param(
            [Parameter(ValueFromPipeline = $true)]
            $Actual,

            [Parameter(Position = 1)]
            $Expected
        )
        if ( $Actual -eq $Expected )
        {
            Write-Host '  match'
        }
        else
        {
            Write-Error "`r`nExpected: $Expected `r`nActual:   $Actual"
        }
    }       
}

Import-Module $mck -Force
Import-Module $stck -Force
Import-Module $pstr -Force