. "$PSScriptRoot\setup.ps1"

function i1 { 'real i1' }
function i2 { "real i2 - $(& ([scriptblock]::Create({i1})))" }

Describe 'mock function called from an unbound scriptblock' {
    New-Mock -FunctionName 'i1' -MockWith { 'fake i1' } | out-null
    It 'invokes mock' {
        $r = i2
        $r | ShouldBe 'real i2 - fake i1'
    }
}

$k = New-Module k {
    function k1 { 'real k1' }
}

$j = New-Module j {
    param($otherModule)

    function j1 { 'real j1' }
    function j2 { "real j2 - $(j1)" }
    function j3 { "real j3 - $(k1)" }

    $x = New-Module x {
        function x1 { "real x1 - $(j1)" }
    }

    New-Module y {
        function y1 { "real y1 - $(j1)" }
    } | Import-Module

    function j4 {
        "real j4 - $(& ([scriptblock]::Create({j1})))"
    }
    function j5 {
        "real j5 - $(& ([scriptblock]::Create({k1})))"
    }
    function j6 {
        Get-Command k1 | % definition
        & $otherModule.NewBoundScriptBlock({
            "real j6 - $(k1)"
        })
    }
} -ArgumentList $k

# nothing special is needed we shadow the function in the top level scope so the module 
# function is never reached
Describe 'mock function inside a module' {
    New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
    It 'invokes mock' {
        $r = j1
        $r | ShouldBe 'fake j1'
    }
}

# we need to run inside of the module scope and mock the function there
Describe 'mock function inside a module called inside that module' { 
    Save-ExecutionContext -Context $ExecutionContext
    &$j { # <- run in j module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
        Run-InTopLevelExecutionContext {
            It 'invokes mock' {
                $r = j2
                $r | ShouldBe 'real j2 - fake j1'
            }
        }
    }
}

Describe 'mock function inside a module called from another module' {
    Save-ExecutionContext -Context $ExecutionContext
    &$j { # <- run in j module scope
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
        Run-InTopLevelExecutionContext {
            It 'invokes mock' {
                $r = j3
                $r | ShouldBe 'real j3 - fake k1'
            }    
        }
    }
}

Describe 'mock function inside one module called from another module inside that module' {
    Save-ExecutionContext -Context $ExecutionContext
    $x = &$j { $x }  # <- get the internal x module from j
    &$x { # <- run in x module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
        Run-InTopLevelExecutionContext {
            It 'invokes mock' {
                $r = x1
                $r | ShouldBe 'real x1 - fake j1'
            }    
        }
    }
}

Describe 'mock function inside one module called from another module imported inside that module' {
    Save-ExecutionContext -Context $ExecutionContext
    $y = &$j { Get-Module y }  # <- normally you would probably import the module and do this instead of having it in variable
    &$y  { # <- run in y module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
        Run-InTopLevelExecutionContext {
            It 'invokes mock' {
                $r = y1
                $r | ShouldBe 'real y1 - fake j1'
            }    
        }
    }
}

Describe 'mock function inside a module invoked from an unbound scriptblock' {
    Save-ExecutionContext -Context $ExecutionContext
    &$j { # <- run in j module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | Out-Null
        Run-InTopLevelExecutionContext {
            It 'invokes mock' {
                $r = j4
                $r | ShouldBe 'real j4 - fake j1'
            }
        }
    }
}

Describe 'mock function inside a module invoked from an unbound scriptblock from another module' {
    Save-ExecutionContext -Context $ExecutionContext
    &$j { # <- run in j module scope
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
        Run-InTopLevelExecutionContext {
            It 'invokes mocks' {
                $r = j5
                $r | ShouldBe 'real j5 - fake k1'
            }
        }
    }

    It 'invokes real function again' {
        $r = j5
        $r | ShouldBe 'real j5 - real k1'
    }
}

# nice try confusing me with using k2 instead of k1 :P :))
Describe 'mock function invoked from a scriptblock late bound to another module' {
    Save-ExecutionContext -Context $ExecutionContext
    &$k { # <- run in k module scope 
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null

        &$j { # <- run in j module scope
            Run-InTopLevelExecutionContext {
                It 'invokes mocks' {
                    $r = j6
                    $r | ShouldBe 'real j6 - fake k1'
                }
            }
        }
    }
}

$l = New-Module -Name l {
    $vl1 = "variable in module l"
    function l1 { "real l1 - $vl1" }
    function l2 { "real l2 - $(l1)" }

    Export-ModuleMember -Function l1
} | Import-Module -Force -PassThru


# think real Pester does something similar for us, but I am not 
# 100% sure it behaves the same as this
$pstr2 = New-Module -Name Pstr2 {
#saves the outer scope excution context for later
    function Save-ExecutionContext { 
        [cmdletbinding()]
        param($Context)
        $script:s = $Context.SessionState
        $script:i =$Context.InvokeCommand
    }
    # run the code in the saved context
    function Run-InTopLevelExecutionContext ([scriptblock] $ScriptBlock) {
        "run through provider on top again"
        $script:i.InvokeScript($script:s, $ScriptBlock.GetNewClosure(), [object[]]@())
    }
} | Import-Module -force


$vl1 = 'abc'

Save-ExecutionContext -Context $ExecutionContext
Run-InTopLevelExecutionContext {$vl1} | Shouldbe 'abc'
# we need to run inside of the module scope to mock
# but we should run back in our top level scope when we want to test the public surface of '
# our module
Describe 'mock function inside a module called inside that module' { 

    &$l { # <- run in l module scope
        New-Mock -FunctionName 'l1' -MockWith { 'fake l1' } | out-null
        
        It 'gives vl1 value from the module scope' {
            $vl1 | ShouldBe 'variable in module l'
        }

        It 'finds the l2 command even though it is not exported' {
            l2
        }

        Run-InTopLevelExecutionContext { 
            It 'keeps vl1 on value from the outer scope' {
                $vl1 | ShouldBe 'abc'
            }

            &$l {
                It 'invokes mock' {
                    $r = l2
                    $r | ShouldBe 'real l2 - fake l1'
                }
            }

            It 'fails to find the command because it is not exported' {
                #doing the assert in place to avoid another scope to think about
                $hadError = $false
                try { 
                    l2
                }
                catch {
                    $hadError = $true
                    write-host "error was thrown, because l2 command was not found, and the is correct"
                }
                if (-not $hadError) { throw "expected error but got none" }
            }
        }
    }
}