. "$PSScriptRoot\setup.ps1"
. "$PSScriptRoot\helpers.ps1"

Save-ScriptScope
$_scope = 'script'

function i1 { 'real i1' }
function i2 { "real i2 - $(& ([scriptblock]::Create({i1})))" }

Describe 'mock function called from an unbound scriptblock' {
    New-Mock -FunctionName 'i1' -MockWith { 'fake i1' } | out-null
    It 'invokes mock' {
        $r = i2
        $r | ShouldBe 'real i2 - fake i1'
    }

    It 'we are in script scope' {
        $_scope | ShouldBe 'script'
    }
}

$k = New-Module k {
    $_scope = 'k'
    function k1 { 'real k1' }
}

$j = New-Module j {
    param($otherModule)
    
    $_scope = 'j'

    function j1 { 'real j1' }
    function j2 { "real j2 - $(j1)" }
    function j3 { "real j3 - $(k1)" }

    $x = New-Module x {
        $_scope = 'x'
        function x1 { "real x1 - $(j1)" }
    }

    New-Module y {
        $_scope = 'y'
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

    It 'we are in script scope' {
        $_scope | ShouldBe 'script'
    }
}

# we need to run inside of the module scope and mock the function there
Describe 'mock function inside a module called inside that module' { 
    Invoke-InModuleScope -Module $j -ScriptBlock { # <- run in j module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null

        It 'we are in j scope' {
            $_scope | ShouldBe 'j'
        }

        Invoke-InScriptScope {
            It 'invokes mock' {
                $r = j2
                $r | ShouldBe 'real j2 - fake j1'
            }

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }
    }
}

Describe 'mock function inside a module called from another module' {
    Invoke-InModuleScope -Module $j -ScriptBlock { # <- run in j module scope
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
        Invoke-InScriptScope {
            It 'invokes mock' {
                $r = j3
                $r | ShouldBe 'real j3 - fake k1'
            }    

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }

        It 'we are in j scope' {
            $_scope | ShouldBe 'j'
        }
    }
}

Describe 'mock function inside one module called from another module inside that module' {
    $x = Invoke-InModuleScope -Module $j -ScriptBlock { $x }  # <- get the internal x module from j
    Invoke-InModuleScope -Module $x -ScriptBlock { # <- run in x module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
        Invoke-InScriptScope {
            It 'invokes mock' {
                $r = x1
                $r | ShouldBe 'real x1 - fake j1'
            }    

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }

        It 'we are in x scope' {
            $_scope | ShouldBe 'x'
        }
    }
}

Describe 'mock function inside one module called from another module imported inside that module' {
    $y = Invoke-InModuleScope -Module $j -ScriptBlock { Get-Module y }  # <- normally you would probably import the module and do this instead of having it in variable
    Invoke-InModuleScope -Module $y -ScriptBlock  { # <- run in y module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | out-null
        Invoke-InScriptScope {
            It 'invokes mock' {
                $r = y1
                $r | ShouldBe 'real y1 - fake j1'
            }    

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }

        It 'we are in y scope' {
            $_scope | ShouldBe 'y'
        }
    }
}

Describe 'mock function inside a module invoked from an unbound scriptblock' {
    Invoke-InModuleScope -Module $j -ScriptBlock { # <- run in j module scope
        New-Mock -FunctionName 'j1' -MockWith { 'fake j1' } | Out-Null
        Invoke-InScriptScope {
            It 'invokes mock' {
                $r = j4
                $r | ShouldBe 'real j4 - fake j1'
            }

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }

        It 'we are in j scope' {
            $_scope | ShouldBe 'j'
        }
    }
}

Describe 'mock function inside a module invoked from an unbound scriptblock from another module' {
    Invoke-InModuleScope -Module $j -ScriptBlock { # <- run in j module scope
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null
        Invoke-InScriptScope {
            It 'invokes mocks' {
                $r = j5
                $r | ShouldBe 'real j5 - fake k1'
            }

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }

        It 'we are in j scope' {
            $_scope | ShouldBe 'j'
        }
    }

    It 'invokes real function again' {
        $r = j5
        $r | ShouldBe 'real j5 - real k1'
    }

    It 'we are in script scope' {
        $_scope | ShouldBe 'script'
    }
}

# nice try confusing me with using k2 instead of k1 :P :))                  #
#                                         wot?  who would do such a thing?  #
Describe 'mock function invoked from a scriptblock late bound to another module' {
    Invoke-InModuleScope -Module $k -ScriptBlock { # <- run in k module scope 
        New-Mock -FunctionName 'k1' -MockWith { 'fake k1' } | out-null

        It 'we are in k scope' {
            $_scope | ShouldBe 'k'
        }

        Invoke-InModuleScope -Module $j -ScriptBlock { # <- run in j module scope

            It 'we are in j scope' {
                $_scope | ShouldBe 'j'
            }

            Invoke-InScriptScope {
                It 'invokes mocks' {
                    $r = j6
                    $r | ShouldBe 'real j6 - fake k1'
                }

                It 'we are in script scope' {
                    $_scope | ShouldBe 'script'
                }
            }
        }
    }
}

$l = New-Module -Name l {
    $_scope = 'l'

    $vl1 = "variable in module l"
    function l1 { "real l1 - $vl1" }
    function l2 { "real l2 - $(l1)" }

    Export-ModuleMember -Function l1
} | Import-Module -Force -PassThru


$vl1 = 'abc'

Invoke-InScriptScope {$vl1} | Shouldbe 'abc'
# we need to run inside of the module scope to mock
# but we should run back in our top level scope when we want to test the public surface of '
# our module
Describe 'mock function inside a module called inside that module' { 

    Invoke-InModuleScope -Module $l -ScriptBlock { # <- run in l module scope
        New-Mock -FunctionName 'l1' -MockWith { 'fake l1' } | out-null
        
        It 'gives vl1 value from the module scope' {
            $vl1 | ShouldBe 'variable in module l'
        }

        It 'finds the l2 command even though it is not exported' {
            l2
        }

        It 'we are in l scope' {
            $_scope | ShouldBe 'l'
        }

        Invoke-InScriptScope { 
            It 'keeps vl1 on value from the outer scope' {
                $vl1 | ShouldBe 'abc'
            }

            Invoke-InModuleScope -Module $l -ScriptBlock {
                It 'invokes mock' {
                    $r = l2
                    $r | ShouldBe 'real l2 - fake l1'
                }

                It 'we are in l scope' {
                    $_scope | ShouldBe 'l'
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

            It 'we are in script scope' {
                $_scope | ShouldBe 'script'
            }
        }
    }
}

# Per PowerShell/PowerShell#4713 dynamic modules do not behave the same as .psm1-backed wrt. scope.
# Test class scope using .psm1-backed modules.

$m = New-Psm1Module m {
    function _m1 { 'real _m1' }
    function m2 { 'real m2' }
    class cm1 {
        [object] Invoke_m1() {
            return _m1
        }
        [object] Invokem2() {
            return m2
        }
    }
    function m3 {
        [cm1]::new()
    }
    function m4 {
        [cm1]::new().Invoke_m1()
    }
    function m5 {
        [cm1]::new().Invokem2()
    }
    Export-ModuleMember -Function m*
}

Describe 'mock function invoked from a class method' {
    New-Mock -FunctionName 'm2' -MockWith { 'fake m2' } | out-null
    class c {
        [object] Invoke() {
            return m2
        }
    }
    It 'invokes mock' {
        $c = [c]::new()

        $r = $c.Invoke()
        $r | ShouldBe 'fake m2'
    }
}

Describe 'mock exported function from a class method inside the module' {
    Invoke-InModuleScope -Module $m -ScriptBlock {
        New-Mock -FunctionName 'm2' -MockWith { 'fake m2' } | Out-Null
        It 'invokes mock' {
            $r = m5
            $r | ShouldBe 'fake m2'
        }
    }
}

Describe 'mock unexported function bound to module invoked from a class method inside the module.' {
    Invoke-InModuleScope -Module $m -ScriptBlock {
        New-Mock -FunctionName '_m1' -MockWith { 'fake _m1' } | Out-Null
        It 'invokes mock' {
            $r = m4
            $r | ShouldBe 'fake _m1'
        }
    }
}

Describe 'mock unexported function bound to module invoked from a class method of an instance originating inside the module but invoked outside the module.' {
    Invoke-InModuleScope -Module $m -ScriptBlock {
        New-Mock -FunctionName '_m1' -MockWith { 'fake _m1' } | Out-Null
        It 'invokes mock' {
            $c = m3

            $r = $c.Invoke_m1()
            $r | ShouldBe 'fake _m1'
        }
    }
}

$ExecutionContext.GetHashCode()
It "asdf" {
    $_scope = 'asdf it'
    &{
        $_scope = 'second level'
        Invoke-InModuleScope -Module $j -ScriptBlock {
            $_scope | ShouldBe 'j'
            Invoke-InModuleScope -Module $k -ScriptBlock {
                $_scope | ShouldBe 'k'
                Invoke-InScriptScope { 
                    $_scope | ShouldBe 'second level'
                }
            }
        }
    }
}